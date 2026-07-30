#!/usr/bin/env bash
# Install the global npm packages declared in npm-globals.txt.
#
# Idempotent: only installs packages that are missing, so a re-apply with no
# list changes performs no network work. Never removes undeclared globals.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SOURCE_DIR/lib/common.sh"

LIST_FILE="${1:-$SOURCE_DIR/npm-globals.txt}"

if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv 2>/dev/null || true)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
export PATH="${PATH:+$PATH:}/opt/homebrew/bin:${HOME}/.local/bin"

# Node comes from nvm, which is not on PATH until its script is sourced.
NVM_SH="${NVM_SH_OVERRIDE:-/opt/homebrew/opt/nvm/nvm.sh}"
if [[ -s "$NVM_SH" ]]; then
  export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"
  # shellcheck source=/dev/null
  source "$NVM_SH"
fi

if [[ ! -f "$LIST_FILE" ]]; then
  warn "npm globals list not found: $LIST_FILE"
  exit 0
fi

if ! command -v npm >/dev/null 2>&1; then
  warn "npm not found; skipping global npm packages"
  exit 0
fi

# Read declared packages, dropping comments and blank lines.
WANTED=()
while IFS= read -r line; do
  line="${line%%#*}"
  line="$(printf '%s' "$line" | tr -d '[:space:]')"
  [[ -n "$line" ]] || continue
  WANTED+=("$line")
done < "$LIST_FILE"

if [[ "${#WANTED[@]}" -eq 0 ]]; then
  log "No global npm packages declared"
  exit 0
fi

log "Checking ${#WANTED[@]} global npm package(s)"

# Resolve installed names once, then diff in Python so scoped specs like
# @scope/pkg@1.2.3 split correctly (only a trailing @version is a version).
MISSING_RAW="$(
  npm ls -g --depth=0 --json 2>/dev/null \
    | python3 -c '
import json, sys

wanted = sys.argv[1:]
try:
    data = json.load(sys.stdin)
except Exception:
    data = {}
installed = set((data.get("dependencies") or {}).keys())


def base_name(spec):
    if spec.startswith("@"):
        rest = spec[1:]
        return "@" + (rest.rsplit("@", 1)[0] if "@" in rest else rest)
    return spec.rsplit("@", 1)[0] if "@" in spec else spec


for spec in wanted:
    if base_name(spec) not in installed:
        print(spec)
' "${WANTED[@]}"
)"

MISSING=()
while IFS= read -r pkg; do
  [[ -n "$pkg" ]] || continue
  MISSING+=("$pkg")
done <<< "$MISSING_RAW"

if [[ "${#MISSING[@]}" -eq 0 ]]; then
  log "All declared global npm packages already installed"
  exit 0
fi

log "Installing ${#MISSING[@]} missing package(s): ${MISSING[*]}"
if ! npm install -g "${MISSING[@]}"; then
  warn "npm install -g reported issues"
  exit 0
fi

log "Global npm packages ready"
