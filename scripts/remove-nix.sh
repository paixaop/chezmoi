#!/usr/bin/env bash
# Completely remove Nix (Determinate installer + nix-darwin + home-manager).
# Never invoked by chezmoi apply — run only after postflight is green.
#
# Order of operations:
#   1. Refuse if required non-Nix tools are missing
#   2. Prefer the official /nix/nix-installer uninstall
#   3. Scrub every leftover the official tool leaves behind on this machine
#   4. Verify nothing Nix-related remains (except ~/.config/nix, intentionally kept)

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SOURCE_DIR/lib/common.sh"

KEEP_CONFIG_NIX=1
FORCE_SCRUB=0

usage() {
  cat <<'EOF'
Usage: remove-nix.sh [--force-scrub] [--also-delete-config]

  --force-scrub         Skip the official uninstaller and only run the scrub pass
                        (useful when /nix/nix-installer is already gone).
  --also-delete-config  Also delete ~/.config/nix (kept by default for rollback).
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --force-scrub) FORCE_SCRUB=1; shift ;;
    --also-delete-config) KEEP_CONFIG_NIX=0; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

log "Nix removal is destructive and irreversible without backups."
if [[ "$KEEP_CONFIG_NIX" -eq 1 ]]; then
  log "Keeping $HOME/.config/nix (pass --also-delete-config to remove it)."
fi

eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || true)"
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

# ---------------------------------------------------------------------------
# Preflight: the replacement toolchain must already work without /nix.
# ---------------------------------------------------------------------------

# nix-homebrew installs a real Cellar/Caskroom but symlinks the brew launcher
# and the whole Library/Homebrew implementation into the store. `brew` keeps
# working right up until /nix disappears, at which point Homebrew is gone and
# cannot repair itself. Check the implementation, not just the entry point.
for hb in /opt/homebrew/bin/brew /opt/homebrew/Library/Homebrew; do
  if [[ -e "$hb" ]] && path_is_nix "$hb"; then
    die "Refusing to remove Nix: Homebrew is Nix-managed ($hb resolves into the store).
     Removing Nix would delete Homebrew itself and leave the Cellar unusable.
     Run scripts/prepare-nix-exit.sh first to install a real Homebrew."
  fi
done
for marker in /opt/homebrew/.managed_by_nix_darwin /opt/homebrew/Library/.homebrew-is-managed-by-nix; do
  if [[ -e "$marker" ]]; then
    die "Refusing to remove Nix: found $marker.
     Homebrew is still owned by nix-homebrew. Run scripts/prepare-nix-exit.sh first."
  fi
done

REQUIRED=(brew chezmoi git gh tmux nvim mise uv direnv)
MISSING=()
NIXED=()
for c in "${REQUIRED[@]}"; do
  p="$(command -v "$c" 2>/dev/null || true)"
  if [[ -z "$p" ]]; then
    MISSING+=("$c")
  elif path_is_nix "$p"; then
    NIXED+=("$c -> $p")
  fi
done
if [[ "${#MISSING[@]}" -gt 0 || "${#NIXED[@]}" -gt 0 ]]; then
  # Report every problem at once; fixing them one error per run is miserable.
  printf 'ERROR: Refusing to remove Nix.\n' >&2
  if [[ "${#MISSING[@]}" -gt 0 ]]; then
    printf '  not installed:  %s\n' "${MISSING[*]}" >&2
  fi
  for entry in "${NIXED[@]:-}"; do
    [[ -n "$entry" ]] && printf '  still from Nix: %s\n' "$entry" >&2
  done
  printf '\n  Run scripts/prepare-nix-exit.sh to install non-Nix replacements.\n' >&2
  exit 1
fi
log "Preflight passed for: ${REQUIRED[*]}"

cat <<'EOF'

This will:
  - run /nix/nix-installer uninstall (Determinate) when present
  - unload every org.nixos.* and systems.determinate.* LaunchDaemon/Agent
  - restore /etc shell files from *.before-nix-darwin / *.backup-before-nix*
  - remove /etc/static and every /etc symlink that pointed into it
  - remove /etc/profile.d/nix.sh, /etc/nix, nix-darwin sudoers/ssh snippets
  - remove the `nix` line from /etc/synthetic.conf
  - remove the Determinate /nix line from /etc/fstab
  - unmount and delete the "Nix Store" APFS volume
  - delete all _nixbld* users and the nixbld group
  - delete the System keychain "Nix Store" volume password
  - delete ~/.nix-*, ~/.local/state/nix, ~/.cache/nix, Library caches
  - delete "/Applications/Nix Apps" and "~/Applications/Home Manager Apps"
  - strip /nix/store and hm-session-vars sources from ~/.bashrc ~/.profile ~/.zprofile

EOF

read -r -p "Type REMOVE-NIX to continue: " confirm
[[ "$confirm" == "REMOVE-NIX" ]] || die "Aborted."

sudo -v

# Keep sudo alive for the long APFS deletion.
while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_KEEPALIVE_PID=$!
trap 'kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true' EXIT

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

bootout_plist() {
  local domain="$1" plist="$2"
  if [[ -f "$plist" ]]; then
    log "Unloading $plist"
    sudo launchctl bootout "$domain" "$plist" 2>/dev/null || true
    # Older installs used unload instead of bootout.
    sudo launchctl unload "$plist" 2>/dev/null || true
    sudo rm -f "$plist"
  fi
}

restore_shell_file() {
  # Prefer the most specific backup the installer or nix-darwin left behind.
  local target="$1" backup
  for backup in \
      "${target}.backup-before-nix-darwin" \
      "${target}.before-nix-darwin" \
      "${target}.backup-before-nix" \
      "${target}.before-nix"; do
    if [[ -f "$backup" ]]; then
      log "Restoring $target from $backup"
      sudo cp "$backup" "$target"
      sudo chmod 644 "$target" 2>/dev/null || true
      sudo rm -f "$backup"
      return 0
    fi
  done
  if [[ -L "$target" ]]; then
    local dest
    dest="$(readlink "$target" 2>/dev/null || true)"
    case "$dest" in
      /etc/static/*|/nix/*)
        log "Removing Nix-managed symlink $target -> $dest"
        sudo rm -f "$target"
        # With no backup the file is now simply gone. For /etc/zprofile that
        # silently removes path_helper and strips /usr/sbin from every login
        # shell, so put Apple's defaults back.
        "$SOURCE_DIR/scripts/restore-etc-shell-files.sh" >/dev/null || \
          warn "Could not restore stock $target; run scripts/restore-etc-shell-files.sh"
        return 0
        ;;
    esac
  fi
  if [[ -f "$target" ]] && grep -Eq '/nix/|nix-daemon\.sh|NIX_' "$target" 2>/dev/null; then
    warn "$target still references Nix and has no backup; removing Nix stanzas"
    sudo cp "$target" "${target}.bak.pre-chezmoi-nix-removal"
    # Drop lines that source the daemon profile or any /nix/store path.
    sudo sed -i '' \
      -e '/nix-daemon\.sh/d' \
      -e '/\/nix\//d' \
      -e '/^# Nix$/d' \
      "$target"
  fi
}

strip_user_shell_nix() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  if ! grep -Eq '/nix/|hm-session-vars|NIX_|nix-daemon\.sh' "$f" 2>/dev/null; then
    return 0
  fi
  log "Stripping Nix references from $f"
  cp "$f" "${f}.bak.pre-chezmoi-nix-removal"
  # Remove source/. lines that pull in nix/store or hm-session-vars, and
  # bare comments that only exist to mark those blocks.
  sed -i '' \
    -e '/hm-session-vars/d' \
    -e '/\/nix\/store\//d' \
    -e '/nix-daemon\.sh/d' \
    -e '/^[[:space:]]*\.[[:space:]]*".*nix.*"/d' \
    -e '/^[[:space:]]*source[[:space:]]*.*nix/d' \
    "$f"
}

remove_if_nix_link() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 0
  if [[ -L "$path" ]]; then
    local dest
    dest="$(readlink "$path" 2>/dev/null || true)"
    case "$dest" in
      /etc/static/*|/nix/*)
        log "Removing $path -> $dest"
        sudo rm -f "$path"
        return 0
        ;;
    esac
  fi
  # Regular files that only exist as nix-darwin drop-ins.
  case "$path" in
    /etc/sudoers.d/*nix*|/etc/ssh/*/100-nix-darwin.conf|/etc/ssh/*/101-authorized-keys.conf|/etc/profile.d/nix.sh)
      log "Removing $path"
      sudo rm -f "$path"
      ;;
  esac
}

edit_out_line() {
  # Remove every line matching extended-regex $2 from file $1.
  local file="$1" pattern="$2" tmp rc
  [[ -f "$file" ]] || return 0
  tmp="$(mktemp)"
  set +e
  grep -Ev "$pattern" "$file" > "$tmp"
  rc=$?
  set -e
  # grep: 0 = matches kept, 1 = every line matched (file emptied), 2 = error
  if [[ "$rc" -gt 1 ]]; then
    warn "Failed to filter $file"
    rm -f "$tmp"
    return 0
  fi
  if ! cmp -s "$file" "$tmp"; then
    log "Editing $file (removing /$pattern/)"
    sudo cp "$tmp" "$file"
  fi
  rm -f "$tmp"
}

# ---------------------------------------------------------------------------
# 1. Official Determinate uninstaller
# ---------------------------------------------------------------------------
if [[ "$FORCE_SCRUB" -eq 0 && -x /nix/nix-installer && -f /nix/receipt.json ]]; then
  log "Running official Determinate uninstall: /nix/nix-installer uninstall --no-confirm"
  # Copy the binary out first — uninstall deletes /nix underneath itself.
  INSTALLER_COPY="$(mktemp -d)/nix-installer"
  sudo cp /nix/nix-installer "$INSTALLER_COPY"
  sudo chmod +x "$INSTALLER_COPY"
  sudo cp /nix/receipt.json "$(dirname "$INSTALLER_COPY")/receipt.json"
  if ! sudo "$INSTALLER_COPY" uninstall --no-confirm "$(dirname "$INSTALLER_COPY")/receipt.json"; then
    warn "Official uninstaller reported errors; continuing with scrub pass"
  fi
  rm -rf "$(dirname "$INSTALLER_COPY")"
else
  if [[ "$FORCE_SCRUB" -eq 1 ]]; then
    log "Skipping official uninstaller (--force-scrub)"
  else
    warn "No /nix/nix-installer + receipt.json; scrubbing manually"
  fi
fi

# ---------------------------------------------------------------------------
# 2. LaunchDaemons / LaunchAgents
# ---------------------------------------------------------------------------
log "Unloading Nix / Determinate launch services"
for plist in \
    /Library/LaunchDaemons/org.nixos.nix-daemon.plist \
    /Library/LaunchDaemons/org.nixos.activate-system.plist \
    /Library/LaunchDaemons/org.nixos.darwin-store.plist \
    /Library/LaunchDaemons/org.nixos.nix-optimise.plist \
    /Library/LaunchDaemons/systems.determinate.nix-installer.nix-hook.plist; do
  bootout_plist system "$plist"
done

# Catch any other org.nixos.* or systems.determinate.* units.
for plist in /Library/LaunchDaemons/org.nixos.*.plist \
             /Library/LaunchDaemons/systems.determinate.*.plist \
             /Library/LaunchAgents/org.nixos.*.plist \
             "$HOME"/Library/LaunchAgents/org.nixos.*.plist; do
  [[ -e "$plist" ]] || continue
  case "$plist" in
    /Library/*) bootout_plist system "$plist" ;;
    *)          bootout_plist "gui/$(id -u)" "$plist" ;;
  esac
done

# ---------------------------------------------------------------------------
# 3. Restore / scrub /etc
# ---------------------------------------------------------------------------
log "Restoring /etc shell and profile files"
for f in /etc/bashrc /etc/zshrc /etc/zprofile /etc/zshenv /etc/bash.bashrc /etc/profile; do
  restore_shell_file "$f"
done

# nix-darwin wires many /etc paths through /etc/static -> /nix/store/...-etc/etc
log "Removing /etc paths managed through /etc/static"
remove_if_nix_link /etc/static
remove_if_nix_link /etc/bashrc
remove_if_nix_link /etc/zshrc
remove_if_nix_link /etc/zprofile
remove_if_nix_link /etc/zshenv
remove_if_nix_link /etc/terminfo
remove_if_nix_link /etc/pam.d/sudo_local
remove_if_nix_link /etc/ssl/certs/ca-certificates.crt
remove_if_nix_link /etc/sudoers.d/10-nix-darwin-extra-config
remove_if_nix_link /etc/ssh/ssh_config.d/100-nix-darwin.conf
remove_if_nix_link /etc/ssh/sshd_config.d/100-nix-darwin.conf
remove_if_nix_link /etc/ssh/sshd_config.d/101-authorized-keys.conf
remove_if_nix_link /etc/profiles/per-user/pedro
remove_if_nix_link /etc/profiles/per-user/"$USER"

# Drop any remaining /etc/profiles tree if empty or only nix links.
if [[ -d /etc/profiles ]]; then
  sudo find /etc/profiles -xtype l -delete 2>/dev/null || true
  sudo find /etc/profiles -type d -empty -delete 2>/dev/null || true
fi

sudo rm -f /etc/profile.d/nix.sh
sudo rm -rf /etc/nix
# bash.bashrc is a Determinate drop-in that only sources nix-daemon.sh.
if [[ -f /etc/bash.bashrc ]] && grep -Eq 'nix-daemon\.sh|^# Nix$' /etc/bash.bashrc; then
  log "Removing Determinate /etc/bash.bashrc"
  sudo rm -f /etc/bash.bashrc
fi

# ---------------------------------------------------------------------------
# 4. synthetic.conf and fstab
# ---------------------------------------------------------------------------
if [[ -f /etc/synthetic.conf ]]; then
  log "Removing 'nix' from /etc/synthetic.conf"
  # Keep the `run` line; drop a bare `nix` entry (with optional whitespace).
  edit_out_line /etc/synthetic.conf '^[[:space:]]*nix([[:space:]]|$)'
  # If the file is now empty, remove it entirely.
  if [[ ! -s /etc/synthetic.conf ]]; then
    sudo rm -f /etc/synthetic.conf
  fi
fi

if [[ -f /etc/fstab ]]; then
  log "Removing Determinate /nix entry from /etc/fstab"
  edit_out_line /etc/fstab '[[:space:]]/nix[[:space:]]|Determinate Nix|/nix apfs'
  if [[ ! -s /etc/fstab ]]; then
    # macOS is fine without /etc/fstab; an empty one is confusing.
    sudo rm -f /etc/fstab
  fi
fi

# ---------------------------------------------------------------------------
# 5. Unmount and delete the Nix Store APFS volume
# ---------------------------------------------------------------------------
if mount | grep -q ' on /nix '; then
  log "Unmounting /nix"
  sudo diskutil unmount force /nix 2>/dev/null || sudo umount -f /nix 2>/dev/null || true
fi

if diskutil list | grep -q 'Nix Store'; then
  log "Deleting APFS volume 'Nix Store'"
  # Prefer UUID from the old fstab backup if needed; diskutil accepts the name.
  sudo diskutil apfs deleteVolume "Nix Store" 2>/dev/null \
    || warn "Could not delete APFS volume 'Nix Store' — delete it in Disk Utility if it remains"
fi

# The synthetic mountpoint can remain as an empty directory after volume deletion.
if [[ -e /nix ]]; then
  log "Removing /nix mountpoint"
  sudo rm -rf /nix 2>/dev/null || warn "/nix still present; it goes away after reboot when synthetic.conf is clean"
fi

sudo rm -rf /run/current-system 2>/dev/null || true

# ---------------------------------------------------------------------------
# 6. Build users and group
# ---------------------------------------------------------------------------
log "Removing Nix build users and group"
# Delete users first so the group membership clears cleanly.
while IFS= read -r u; do
  [[ -n "$u" ]] || continue
  log "  dscl delete user $u"
  sudo dscl . -delete "/Users/$u" 2>/dev/null || true
done < <(dscl . -list /Users 2>/dev/null | grep -E '^_nixbld[0-9]+$' || true)

if dscl . -read /Groups/nixbld >/dev/null 2>&1; then
  log "  dscl delete group nixbld"
  sudo dscl . -delete /Groups/nixbld 2>/dev/null || true
fi

# System keychain password used by org.nixos.darwin-store to unlock the volume.
if security find-generic-password -a "Nix Store" -s "Nix Store" >/dev/null 2>&1; then
  log "Removing System keychain password for 'Nix Store'"
  sudo security delete-generic-password -a "Nix Store" -s "Nix Store" /Library/Keychains/System.keychain >/dev/null 2>&1 \
    || warn "Could not delete System keychain 'Nix Store' password"
fi

# ---------------------------------------------------------------------------
# 7. Per-user state and Application leftovers
# ---------------------------------------------------------------------------
log "Removing per-user Nix state"
rm -rf \
  "$HOME/.nix-profile" \
  "$HOME/.nix-defexpr" \
  "$HOME/.nix-channels" \
  "$HOME/.local/state/nix" \
  "$HOME/.cache/nix" \
  "$HOME/Library/Caches/org.nixos.nix" \
  "$HOME/Library/Caches/nix" \
  "$HOME/Library/Application Support/nix" \
  "$HOME/Library/Application Support/org.nixos.nix"

# Root may have its own profile leftovers.
sudo rm -rf /var/root/.nix-profile /var/root/.nix-defexpr /var/root/.nix-channels \
  /var/root/.local/state/nix /var/root/.cache/nix 2>/dev/null || true

log "Removing Nix application folders"
sudo rm -rf "/Applications/Nix Apps"
rm -rf "$HOME/Applications/Home Manager Apps"

# ---------------------------------------------------------------------------
# 8. User shell rc files (chezmoi will rewrite .zshrc/.zprofile on next apply)
# ---------------------------------------------------------------------------
for f in "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.profile" "$HOME/.zprofile" "$HOME/.zshrc"; do
  strip_user_shell_nix "$f"
done

if [[ "$KEEP_CONFIG_NIX" -eq 0 ]]; then
  log "Deleting $HOME/.config/nix"
  rm -rf "$HOME/.config/nix"
fi

# ---------------------------------------------------------------------------
# 9. Verification
# ---------------------------------------------------------------------------
log "Verifying Nix is gone"
FAILURES=0
check_absent() {
  local path="$1"
  if [[ -e "$path" || -L "$path" ]]; then
    # /nix may linger as an empty synthetic dir until reboot.
    if [[ "$path" == "/nix" ]] && [[ -d /nix ]] && [[ -z "$(ls -A /nix 2>/dev/null || true)" ]]; then
      warn "/nix is an empty mountpoint; reboot to clear the synthetic entry"
      return 0
    fi
    printf '  FAIL  still present: %s\n' "$path"
    FAILURES=$((FAILURES + 1))
  else
    printf '  ok    absent: %s\n' "$path"
  fi
}

check_absent /nix
check_absent /etc/nix
check_absent /etc/static
check_absent /run/current-system
check_absent /Library/LaunchDaemons/org.nixos.nix-daemon.plist
check_absent /Library/LaunchDaemons/org.nixos.darwin-store.plist
check_absent /Library/LaunchDaemons/org.nixos.activate-system.plist
check_absent /Library/LaunchDaemons/org.nixos.nix-optimise.plist
check_absent /Library/LaunchDaemons/systems.determinate.nix-installer.nix-hook.plist
check_absent "$HOME/.nix-profile"
check_absent "$HOME/.nix-defexpr"
check_absent "$HOME/.nix-channels"
check_absent "$HOME/.local/state/nix"
check_absent "/Applications/Nix Apps"
check_absent "$HOME/Applications/Home Manager Apps"

if dscl . -list /Users 2>/dev/null | grep -qE '^_nixbld'; then
  printf '  FAIL  _nixbld* users still exist\n'
  FAILURES=$((FAILURES + 1))
else
  printf '  ok    no _nixbld* users\n'
fi

if dscl . -read /Groups/nixbld >/dev/null 2>&1; then
  printf '  FAIL  group nixbld still exists\n'
  FAILURES=$((FAILURES + 1))
else
  printf '  ok    no nixbld group\n'
fi

if diskutil list 2>/dev/null | grep -q 'Nix Store'; then
  printf '  FAIL  APFS volume "Nix Store" still exists\n'
  FAILURES=$((FAILURES + 1))
else
  printf '  ok    no "Nix Store" APFS volume\n'
fi

if [[ -f /etc/fstab ]] && grep -Eq '[[:space:]]/nix[[:space:]]|Determinate Nix' /etc/fstab; then
  printf '  FAIL  /etc/fstab still mounts /nix\n'
  FAILURES=$((FAILURES + 1))
else
  printf '  ok    /etc/fstab has no /nix entry\n'
fi

if [[ -f /etc/synthetic.conf ]] && grep -Eq '^[[:space:]]*nix([[:space:]]|$)' /etc/synthetic.conf; then
  printf '  FAIL  /etc/synthetic.conf still declares nix\n'
  FAILURES=$((FAILURES + 1))
else
  printf '  ok    /etc/synthetic.conf has no nix entry\n'
fi

# PATH smoke-test in a clean login-ish environment.
if env -i HOME="$HOME" PATH="/usr/bin:/bin:/usr/sbin:/sbin:/opt/homebrew/bin" \
    bash -lc 'command -v nix || command -v nix-env || command -v nix-shell' >/dev/null 2>&1; then
  printf '  FAIL  nix binaries still resolvable on a clean PATH\n'
  FAILURES=$((FAILURES + 1))
else
  printf '  ok    nix binaries not on a clean PATH\n'
fi

echo
if [[ "$FAILURES" -gt 0 ]]; then
  warn "$FAILURES leftover(s) remain. Reboot and re-run with --force-scrub, or delete manually."
  warn "Touch ID sudo: re-run chezmoi apply so it recreates /etc/pam.d/sudo_local."
  exit 1
fi

log "Nix fully removed."
log "Reboot recommended so the synthetic /nix entry and any cached mounts clear."
log "Then: open a new shell, confirm 'command -v nix' is empty, and re-apply chezmoi"
log "so Touch ID sudo (/etc/pam.d/sudo_local) is recreated."
if [[ "$KEEP_CONFIG_NIX" -eq 1 ]]; then
  log "Kept for rollback: $HOME/.config/nix"
fi
