#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'chmod -R u+rwX "$TEST_ROOT" 2>/dev/null || true; rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export NIX_CONFIG_DIR="$HOME/.config/nix"
export BACKUP_DIR="$TEST_ROOT/backups"
export BACKUP_TIMESTAMP="20260729-222100"

mkdir -p "$NIX_CONFIG_DIR" "$HOME/.config" "$TEST_ROOT/nix-store/phoenix"
printf 'flake contents\n' >"$NIX_CONFIG_DIR/flake.nix"
printf 'phoenix contents\n' >"$TEST_ROOT/nix-store/phoenix/phoenix.js"
ln -s "$TEST_ROOT/nix-store/phoenix" "$HOME/.config/phoenix"

# Mimic the read-only Nix store so cleanup of copied files is exercised.
chmod -R a-w "$TEST_ROOT/nix-store"

staging_before="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'nix-backup.*' | wc -l | tr -d ' ')"

"$SCRIPT_DIR/backup-nix-config.sh" >/dev/null

staging_after="$(find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'nix-backup.*' | wc -l | tr -d ' ')"
if [[ "$staging_after" != "$staging_before" ]]; then
  printf 'staging directory was not cleaned up\n' >&2
  exit 1
fi

archive="$BACKUP_DIR/nix-backup-$BACKUP_TIMESTAMP.tar.gz"
checksum="$archive.sha256"

[[ -f "$archive" ]] || {
  printf 'missing archive: %s\n' "$archive" >&2
  exit 1
}
[[ -f "$checksum" ]] || {
  printf 'missing checksum: %s\n' "$checksum" >&2
  exit 1
}

contents="$(tar -tzf "$archive")"
grep -q 'nix-backup/config/nix/flake.nix' <<<"$contents"
grep -q 'nix-backup/home/.config/phoenix/phoenix.js' <<<"$contents"
grep -q 'nix-backup/metadata/system.txt' <<<"$contents"

(cd "$BACKUP_DIR" && shasum -a 256 -c "$(basename "$checksum")") >/dev/null

extract_dir="$TEST_ROOT/extract"
mkdir -p "$extract_dir"
tar -xzf "$archive" -C "$extract_dir"
restored_file="$extract_dir/nix-backup/home/.config/phoenix/phoenix.js"
[[ -w "$restored_file" ]] || {
  printf 'restored file is not writable: %s\n' "$restored_file" >&2
  exit 1
}

printf 'backup-nix-config test passed\n'
