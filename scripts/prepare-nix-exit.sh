#!/usr/bin/env bash
# Prepare this machine to survive `remove-nix.sh`.
#
# The blocker is that nix-homebrew owns Homebrew itself:
#   /opt/homebrew/bin/brew          -> /nix/store/...-brew
#   /opt/homebrew/Library/Homebrew  -> /nix/store/...-brew-*/Library/Homebrew
# The Cellar, Caskroom, and Taps are real directories and survive, but the brew
# implementation vanishes with the store, and Homebrew cannot reinstall itself
# without a working brew. So the real Homebrew must be restored *while Nix is
# still present*, then used to install the replacement toolchain.
#
# This script is idempotent and never touches /nix. Run it before remove-nix.sh.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SOURCE_DIR/lib/common.sh"

BREW_PREFIX="/opt/homebrew"
BREW_REPO_URL="https://github.com/Homebrew/brew"
DRY_RUN=0
SKIP_INSTALL=0

usage() {
  cat <<'EOF'
Usage: prepare-nix-exit.sh [--dry-run] [--skip-install]

Restores a real (non-Nix) Homebrew into /opt/homebrew and installs the
replacement toolchain from the Brewfile, so that remove-nix.sh can run.

  --dry-run       Show what would change; make no modifications.
  --skip-install  Restore Homebrew only; do not install replacement formulae.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --skip-install|--skip-bundle) SKIP_INSTALL=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) die "unknown argument: $1" ;;
  esac
done

run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  would run: %s\n' "$*"
  else
    "$@"
  fi
}

sudo_run() {
  if [[ "$DRY_RUN" -eq 1 ]]; then
    printf '  would run: sudo %s\n' "$*"
  else
    sudo "$@"
  fi
}

# ---------------------------------------------------------------------------
# 1. Assess what is Nix-owned
# ---------------------------------------------------------------------------
log "Inspecting Homebrew at $BREW_PREFIX"

[[ -d "$BREW_PREFIX" ]] || die "$BREW_PREFIX does not exist; install Homebrew normally first."

brew_is_nix=0
if [[ -e "$BREW_PREFIX/bin/brew" ]] && path_is_nix "$BREW_PREFIX/bin/brew"; then
  brew_is_nix=1
fi
if [[ -e "$BREW_PREFIX/Library/Homebrew" ]] && path_is_nix "$BREW_PREFIX/Library/Homebrew"; then
  brew_is_nix=1
fi
[[ -e "$BREW_PREFIX/.managed_by_nix_darwin" ]] && brew_is_nix=1
[[ -e "$BREW_PREFIX/Library/.homebrew-is-managed-by-nix" ]] && brew_is_nix=1

if [[ "$brew_is_nix" -eq 0 ]]; then
  log "Homebrew is already independent of Nix."
else
  warn "Homebrew is currently provided by nix-homebrew and must be replaced."

  # Cellar/Caskroom/Taps are real and must be preserved. Confirm before touching
  # anything, because losing them means reinstalling every package.
  for keep in Cellar Caskroom Library/Taps; do
    if [[ -L "$BREW_PREFIX/$keep" ]]; then
      die "$BREW_PREFIX/$keep is a symlink; refusing to proceed (expected a real directory)."
    fi
  done
  log "Cellar, Caskroom, and Taps are real directories and will be preserved."

  # -------------------------------------------------------------------------
  # 2. Remove the Nix-owned entry points
  # -------------------------------------------------------------------------
  # nix-darwin may have made these root-owned and read-only.
  if [[ -L "$BREW_PREFIX/bin/brew" ]]; then
    log "Removing Nix brew launcher symlink"
    sudo_run rm -f "$BREW_PREFIX/bin/brew"
  fi
  if [[ -L "$BREW_PREFIX/Library/Homebrew" ]]; then
    log "Removing Nix Library/Homebrew symlink"
    sudo_run rm -f "$BREW_PREFIX/Library/Homebrew"
  fi
  for marker in "$BREW_PREFIX/.managed_by_nix_darwin" "$BREW_PREFIX/Library/.homebrew-is-managed-by-nix"; do
    if [[ -e "$marker" ]]; then
      log "Removing marker $marker"
      sudo_run rm -rf "$marker"
    fi
  done

  # -------------------------------------------------------------------------
  # 3. Materialise the real Homebrew repository in place
  # -------------------------------------------------------------------------
  # /opt/homebrew is a non-empty, non-git directory, so `git clone` refuses.
  # This is the same init/fetch/reset dance Homebrew's own install.sh performs
  # for a pre-existing prefix; `reset --hard` does not delete untracked files,
  # so Cellar and Caskroom are untouched.
  # GNU coreutils may shadow BSD stat in PATH, and they disagree on -f.
  owner="$(/usr/bin/stat -f '%Su' "$BREW_PREFIX")"
  if [[ "$owner" != "$(id -un)" ]]; then
    log "Taking ownership of $BREW_PREFIX (currently $owner)"
    sudo_run chown -R "$(id -un):admin" "$BREW_PREFIX"
  fi

  if [[ ! -d "$BREW_PREFIX/.git" ]]; then
    log "Initialising the Homebrew git repository in $BREW_PREFIX"
    run git -C "$BREW_PREFIX" init -q
    run git -C "$BREW_PREFIX" remote add origin "$BREW_REPO_URL"
  fi

  log "Fetching Homebrew (this downloads the real brew implementation)"
  run git -C "$BREW_PREFIX" fetch --force --depth=1 origin main
  run git -C "$BREW_PREFIX" reset --hard origin/main

  if [[ "$DRY_RUN" -eq 0 ]]; then
    [[ -x "$BREW_PREFIX/bin/brew" ]] || die "brew launcher missing after restore"
    [[ -d "$BREW_PREFIX/Library/Homebrew" && ! -L "$BREW_PREFIX/Library/Homebrew" ]] \
      || die "Library/Homebrew is still not a real directory"
    log "Real Homebrew restored."
  fi
fi

# ---------------------------------------------------------------------------
# 4. Install the replacement toolchain
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" -eq 0 ]]; then
  eval "$("$BREW_PREFIX/bin/brew" shellenv)"
fi
export PATH="$BREW_PREFIX/bin:$HOME/.local/bin:$PATH"

if [[ "$SKIP_INSTALL" -eq 0 ]]; then
  # Keep this deliberately small. Installing the full Brewfile here makes Nix
  # removal depend on unrelated GUI apps, third-party taps, and optional tools.
  # `neovim` provides the required `nvim` command.
  MIGRATION_FORMULAE=(
    chezmoi
    git
    gh
    tmux
    neovim
    mise
    uv
    direnv
  )
  log "Installing the minimal non-Nix replacement toolchain"
  run brew update --quiet
  run brew install "${MIGRATION_FORMULAE[@]}"
fi

# ---------------------------------------------------------------------------
# 5. Report what still comes from Nix
# ---------------------------------------------------------------------------
log "Checking the toolchain remove-nix.sh requires"
REQUIRED=(brew chezmoi git gh tmux nvim mise uv direnv)
remaining=0
for c in "${REQUIRED[@]}"; do
  # Re-resolve rather than trusting the shell's command hash table.
  p="$(PATH="$PATH" command -v "$c" 2>/dev/null || true)"
  if [[ -z "$p" ]]; then
    printf '  %-9s MISSING\n' "$c"
    remaining=$((remaining + 1))
  elif path_is_nix "$p"; then
    printf '  %-9s NIX      %s\n' "$c" "$p"
    remaining=$((remaining + 1))
  else
    printf '  %-9s ok       %s\n' "$c" "$p"
  fi
done

echo
if [[ "$remaining" -eq 0 ]]; then
  log "Ready. Open a NEW shell, re-check, then run scripts/remove-nix.sh"
else
  warn "$remaining tool(s) still unresolved."
  warn "Nix-provided tools win because /run/current-system and"
  warn "/etc/profiles/per-user precede /opt/homebrew in PATH. Start a new shell"
  warn "(the chezmoi .zprofile puts Homebrew first) and run this script again."
fi
