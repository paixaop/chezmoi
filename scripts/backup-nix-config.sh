#!/usr/bin/env bash
# Back up the Nix configuration and Nix-managed user files.
# This deliberately does not archive the /nix store.

set -euo pipefail
umask 077

NIX_CONFIG_DIR="${NIX_CONFIG_DIR:-$HOME/.config/nix}"
BACKUP_DIR="${BACKUP_DIR:-$HOME/nix-backups}"
BACKUP_TIMESTAMP="${BACKUP_TIMESTAMP:-$(date +%Y%m%d-%H%M%S)}"
ARCHIVE="$BACKUP_DIR/nix-backup-$BACKUP_TIMESTAMP.tar.gz"
CHECKSUM="$ARCHIVE.sha256"

if [[ ! -d "$NIX_CONFIG_DIR" ]]; then
  printf 'ERROR: Nix config directory not found: %s\n' "$NIX_CONFIG_DIR" >&2
  exit 1
fi

if [[ -e "$ARCHIVE" || -e "$CHECKSUM" ]]; then
  printf 'ERROR: Backup already exists for timestamp %s\n' "$BACKUP_TIMESTAMP" >&2
  exit 1
fi

mkdir -p "$BACKUP_DIR"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nix-backup.XXXXXX")"

cleanup() {
  [[ -d "$STAGING_DIR" ]] || return 0
  chmod -R u+rwX "$STAGING_DIR" 2>/dev/null || true
  rm -rf "$STAGING_DIR"
}
trap cleanup EXIT

BACKUP_ROOT="$STAGING_DIR/nix-backup"
mkdir -p "$BACKUP_ROOT/config" "$BACKUP_ROOT/home" "$BACKUP_ROOT/metadata"

printf '==> Copying Nix configuration\n'
cp -R -L "$NIX_CONFIG_DIR" "$BACKUP_ROOT/config/nix"

copy_home_path() {
  local relative_path="$1"
  local source_path="$HOME/$relative_path"
  local target_path="$BACKUP_ROOT/home/$relative_path"

  if [[ ! -e "$source_path" && ! -L "$source_path" ]]; then
    return
  fi

  mkdir -p "$(dirname "$target_path")"
  if [[ -d "$source_path" ]]; then
    cp -R -L "$source_path" "$target_path"
  else
    cp -L "$source_path" "$target_path"
  fi
  printf '==> Copied ~/%s\n' "$relative_path"
}

# Active home-manager outputs and files replaced by the chezmoi migration.
# -L dereferences Nix store symlinks so the archive remains usable after Nix removal.
HOME_PATHS=(
  ".zshrc"
  ".gitconfig"
  ".gitignore_global"
  ".tmux.conf"
  ".tmux"
  ".config/nvim"
  ".config/phoenix"
  ".config/direnv"
  ".cargo/config.toml"
  ".markdownlint-cli2.jsonc"
  ".markdownlint.jsonc"
  "bin/tmux-save-layout"
  "bin/tmux-load-layout"
)

for path in "${HOME_PATHS[@]}"; do
  copy_home_path "$path"
done

{
  printf 'created_at=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf 'hostname=%s\n' "$(hostname)"
  printf 'user=%s\n' "$(id -un)"
  printf 'os=%s\n' "$(uname -a)"
  printf 'nix_config_dir=%s\n' "$NIX_CONFIG_DIR"
  printf 'nix=%s\n' "$(command -v nix 2>/dev/null || printf 'not found')"
  printf 'darwin_rebuild=%s\n' "$(command -v darwin-rebuild 2>/dev/null || printf 'not found')"
  if command -v nix >/dev/null 2>&1; then
    printf 'nix_version=%s\n' "$(nix --version 2>/dev/null || printf 'unknown')"
  fi
  if command -v scutil >/dev/null 2>&1; then
    printf 'computer_name=%s\n' "$(scutil --get ComputerName 2>/dev/null || true)"
    printf 'host_name=%s\n' "$(scutil --get HostName 2>/dev/null || true)"
    printf 'local_host_name=%s\n' "$(scutil --get LocalHostName 2>/dev/null || true)"
  fi
  if [[ -L /run/current-system ]]; then
    printf 'current_system=%s\n' "$(readlink /run/current-system)"
  fi
} >"$BACKUP_ROOT/metadata/system.txt"

# Nix store copies are read-only; restore the owner write bit so the archive is usable.
chmod -R u+rwX "$BACKUP_ROOT"

printf '==> Creating %s\n' "$ARCHIVE"
tar -czf "$ARCHIVE" -C "$STAGING_DIR" nix-backup

(
  cd "$BACKUP_DIR"
  shasum -a 256 "$(basename "$ARCHIVE")" >"$(basename "$CHECKSUM")"
)

printf '==> Verifying archive\n'
tar -tzf "$ARCHIVE" >/dev/null
(
  cd "$BACKUP_DIR"
  shasum -a 256 -c "$(basename "$CHECKSUM")" >/dev/null
)

printf '\nBackup complete:\n  %s\n  %s\n' "$ARCHIVE" "$CHECKSUM"
printf 'The /nix store was not archived.\n'
