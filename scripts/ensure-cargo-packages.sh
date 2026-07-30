#!/usr/bin/env bash
# Install the cargo binaries declared in cargo-packages.txt.
#
# Idempotent: only missing crates are built, so a re-apply with no list
# changes does no work. Never removes crates that are not declared.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SOURCE_DIR/lib/common.sh"

LIST_FILE="${1:-$SOURCE_DIR/cargo-packages.txt}"

if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv 2>/dev/null || true)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
export PATH="${PATH:+$PATH:}/opt/homebrew/bin:${HOME}/.cargo/bin"

if [[ ! -f "$LIST_FILE" ]]; then
  warn "cargo package list not found: $LIST_FILE"
  exit 0
fi

if ! command -v cargo >/dev/null 2>&1; then
  warn "cargo not found; skipping cargo packages (mise provides the rust toolchain)"
  exit 0
fi

WANTED=()
while IFS= read -r line; do
  line="${line%%#*}"
  line="$(printf '%s' "$line" | tr -d '[:space:]')"
  [[ -n "$line" ]] || continue
  WANTED+=("$line")
done < "$LIST_FILE"

if [[ "${#WANTED[@]}" -eq 0 ]]; then
  log "No cargo packages declared"
  exit 0
fi

log "Checking ${#WANTED[@]} cargo package(s)"

# `cargo install --list` prints "crate vX.Y.Z:" headers with indented binaries.
INSTALLED="$(cargo install --list 2>/dev/null | awk '/^[^[:space:]]/ {print $1}' || true)"

MISSING=()
for crate in "${WANTED[@]}"; do
  if printf '%s\n' "$INSTALLED" | grep -Fxq "$crate"; then
    continue
  fi
  MISSING+=("$crate")
done

if [[ "${#MISSING[@]}" -eq 0 ]]; then
  log "All declared cargo packages already installed"
  exit 0
fi

# binstall pulls prebuilt binaries; building these from source takes minutes.
if command -v cargo-binstall >/dev/null 2>&1; then
  log "Installing ${#MISSING[@]} crate(s) via cargo-binstall: ${MISSING[*]}"
  if cargo binstall --no-confirm "${MISSING[@]}"; then
    log "Cargo packages ready"
    exit 0
  fi
  warn "cargo-binstall failed; falling back to cargo install"
fi

log "Installing ${#MISSING[@]} crate(s) via cargo install: ${MISSING[*]}"
for crate in "${MISSING[@]}"; do
  cargo install "$crate" || warn "cargo install $crate failed"
done

log "Cargo packages ready"
