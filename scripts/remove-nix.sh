#!/usr/bin/env bash
# Manually remove Nix after chezmoi postflight succeeds.
# Never invoked by chezmoi apply.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SOURCE_DIR/lib/common.sh"

log "Nix removal is destructive and irreversible without backups."
log "This script will NOT delete $HOME/.config/nix"

eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || true)"
export PATH="/opt/homebrew/bin:$HOME/.local/bin:$PATH"

REQUIRED=(brew chezmoi git gh tmux nvim mise uv direnv)
for c in "${REQUIRED[@]}"; do
  p="$(command -v "$c" 2>/dev/null || true)"
  if [[ -z "$p" ]]; then
    die "Refusing to remove Nix: $c not found. Run bootstrap/apply first."
  fi
  if path_is_nix "$p"; then
    die "Refusing to remove Nix: $c still resolves to $p"
  fi
done

log "Preflight passed for: ${REQUIRED[*]}"
cat <<'EOF'

About to:
  - unload org.nixos.nix-daemon / org.nixos.activate-system
  - delete /nix
  - delete /etc/nix and related profile snippets
  - delete ~/.nix-profile, ~/.nix-defexpr, ~/.nix-channels, ~/.local/state/nix
  - delete Nix caches under ~/Library

EOF

read -r -p "Type REMOVE-NIX to continue: " confirm
[[ "$confirm" == "REMOVE-NIX" ]] || die "Aborted."

sudo -v

sudo launchctl bootout system /Library/LaunchDaemons/org.nixos.nix-daemon.plist 2>/dev/null || true
sudo launchctl bootout system /Library/LaunchDaemons/org.nixos.activate-system.plist 2>/dev/null || true
sudo rm -f /Library/LaunchDaemons/org.nixos.nix-daemon.plist
sudo rm -f /Library/LaunchDaemons/org.nixos.activate-system.plist
rm -f "$HOME/Library/LaunchAgents/org.nixos.nix-daemon.plist"

sudo rm -rf /nix
sudo rm -rf /etc/nix

# The Nix installer leaves the originals next to each file it replaced.
# Restore them; only remove a shell file when a backup can take its place,
# otherwise the system is left without /etc/zshrc at all.
restore_shell_file() {
  local target="$1" backup
  for backup in "${target}.backup-before-nix-darwin" "${target}.backup-before-nix"; do
    if [[ -f "$backup" ]]; then
      log "Restoring $target from $backup"
      sudo cp "$backup" "$target"
      sudo rm -f "$backup"
      return 0
    fi
  done
  if [[ -L "$target" ]]; then
    log "Removing dangling Nix symlink $target"
    sudo rm -f "$target"
    return 0
  fi
  if [[ -f "$target" ]] && grep -q '/nix/' "$target" 2>/dev/null; then
    warn "$target references /nix but has no backup; edit it manually"
  fi
  return 0
}

for f in /etc/bashrc /etc/zshrc /etc/zprofile /etc/bash.bashrc; do
  restore_shell_file "$f"
done

rm -rf "$HOME/.nix-profile" "$HOME/.nix-defexpr" "$HOME/.nix-channels" "$HOME/.local/state/nix"
rm -rf "$HOME/Library/Caches/org.nixos.nix" "$HOME/Library/Application Support/nix" "$HOME/.cache/nix"

sudo rm -rf /run/current-system 2>/dev/null || true

log "Nix removal attempted. Open a new shell and verify commands no longer resolve under /nix."
log "Kept: $HOME/.config/nix"
