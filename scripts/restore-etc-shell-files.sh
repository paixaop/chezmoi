#!/usr/bin/env bash
# Restore the stock macOS /etc shell files that Nix removal deleted.
#
# nix-darwin replaces /etc/zprofile, /etc/zshrc, and /etc/bashrc with symlinks
# into /nix/store. Removing Nix deletes the symlinks, and when no
# *.before-nix-darwin backup exists there is nothing left to restore, so the
# files simply vanish. The important casualty is /etc/zprofile: it is what runs
# path_helper, which builds PATH from /etc/paths and /etc/paths.d. Without it a
# login shell loses /usr/local/bin, /usr/sbin, and /sbin, so commands such as
# scutil and systemsetup stop resolving (including under sudo).
#
# The contents below are Apple's defaults. Existing files are never modified,
# so a customised /etc file is left alone.
#
# ETC_DIR and NO_SUDO exist so the test suite can run against a fixture.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SOURCE_DIR/lib/common.sh"

ETC_DIR="${ETC_DIR:-/etc}"
NO_SUDO="${NO_SUDO:-0}"

maybe_sudo() {
  if [[ "$NO_SUDO" == "1" ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

write_file() {
  local path="$1" content="$2"
  if [[ -e "$path" ]]; then
    return 1
  fi
  # `printf | sudo tee` hides tee's exit status behind the pipeline, so confirm
  # the file actually landed rather than trusting the command to have worked.
  printf '%s\n' "$content" | maybe_sudo tee "$path" >/dev/null 2>&1 || true
  if [[ ! -s "$path" ]]; then
    return 2
  fi
  maybe_sudo chmod 644 "$path" 2>/dev/null || true
  return 0
}

# Quoted heredocs: this is literal file content and must never be expanded.
ZPROFILE="$(cat <<'EOF'
# System-wide profile for interactive zsh(1) login shells.

# Setup user specific overrides for this in ~/.zprofile. See zshbuiltins(1)
# and zshoptions(1) for more details.

if [ -x /usr/libexec/path_helper ]; then
	eval `/usr/libexec/path_helper -s`
fi
EOF
)"

ZSHRC="$(cat <<'EOF'
# System-wide profile for interactive zsh(1) shells.

# Correctly display UTF-8 with combining characters.
if [[ "$(locale LC_CTYPE)" == "UTF-8" ]]; then
	setopt combiningchars
fi

disable log

[ -r /etc/zshrc_$TERM_PROGRAM ] && . /etc/zshrc_$TERM_PROGRAM
EOF
)"

BASHRC="$(cat <<'EOF'
# System-wide .bashrc file for interactive bash(1) shells.
if [ -z "$PS1" ]; then
   return
fi

PS1='\h:\W \u\$ '
# Make bash check its window size after a process completes
shopt -s checkwinsize

[ -r "/etc/bashrc_$TERM_PROGRAM" ] && . "/etc/bashrc_$TERM_PROGRAM"
EOF
)"

if [[ "$NO_SUDO" != "1" ]] && ! sudo -n true 2>/dev/null; then
  log "This writes to $ETC_DIR and needs sudo."
  sudo -v || die "sudo authentication failed; re-run from a terminal"
fi

restored=0
failed=0
for spec in "zprofile:$ZPROFILE" "zshrc:$ZSHRC" "bashrc:$BASHRC"; do
  name="${spec%%:*}"
  body="${spec#*:}"
  write_file "$ETC_DIR/$name" "$body" && rc=0 || rc=$?
  case "$rc" in
    0) log "Restored $ETC_DIR/$name"; restored=$((restored + 1)) ;;
    1) log "Keeping existing $ETC_DIR/$name" ;;
    *) warn "Failed to write $ETC_DIR/$name"; failed=$((failed + 1)) ;;
  esac
done

# Apple ships /etc/bashrc, not /etc/bash.bashrc — the latter is a nix-darwin
# artifact. Stripping its Nix block line-by-line leaves a dangling `fi`, which
# is a syntax error for every shell that sources it. Remove it when nothing of
# substance survives; keep it if the user put real content there.
BASH_BASHRC="$ETC_DIR/bash.bashrc"
if [[ -f "$BASH_BASHRC" ]] && ! bash -n "$BASH_BASHRC" 2>/dev/null; then
  meaningful="$(grep -vE '^[[:space:]]*($|#|fi[[:space:]]*$)' "$BASH_BASHRC" || true)"
  if [[ -z "$meaningful" ]]; then
    log "Removing $BASH_BASHRC (leftover Nix stub with an orphan 'fi')"
    maybe_sudo rm -f "$BASH_BASHRC" 2>/dev/null || true
    if [[ -e "$BASH_BASHRC" ]]; then
      warn "Failed to remove $BASH_BASHRC"
      failed=$((failed + 1))
    else
      restored=$((restored + 1))
    fi
  else
    warn "$BASH_BASHRC has a syntax error but also has real content; leaving it alone"
  fi
fi

if [[ "$failed" -gt 0 ]]; then
  die "$failed file(s) could not be written. Re-run from a terminal so sudo can prompt."
fi

if [[ "$restored" -eq 0 ]]; then
  log "Nothing to restore; /etc shell files are intact."
else
  log "Restored $restored file(s). Open a new login shell to pick up PATH."
fi
