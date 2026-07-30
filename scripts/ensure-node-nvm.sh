#!/usr/bin/env bash
# Install the latest Node via nvm and make it the default.
#
# nvm owns Node on this machine: mise declares no node runtime and the
# Brewfile does not install a system node. Idempotent — re-running when the
# latest version is already the default performs no network work.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SOURCE_DIR/lib/common.sh"

if command -v brew >/dev/null 2>&1; then
  eval "$(brew shellenv 2>/dev/null || true)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

NVM_SH="${NVM_SH_OVERRIDE:-/opt/homebrew/opt/nvm/nvm.sh}"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

if [[ ! -s "$NVM_SH" ]]; then
  warn "nvm not found at $NVM_SH; it is declared in the Brewfile"
  exit 0
fi

mkdir -p "$NVM_DIR"

# nvm aborts outright when npm declares a global prefix, which the pre-chezmoi
# setup did. Retire that setting rather than letting every nvm call fail.
NPMRC="$HOME/.npmrc"
if [[ -f "$NPMRC" ]] && grep -Eq '^[[:space:]]*prefix[[:space:]]*=' "$NPMRC"; then
  backup="${NPMRC}.bak.$(date +%Y%m%d%H%M%S)"
  warn "Removing npm 'prefix' from $NPMRC (incompatible with nvm); backup: $backup"
  cp "$NPMRC" "$backup"
  grep -Ev '^[[:space:]]*prefix[[:space:]]*=' "$backup" > "$NPMRC"
fi

# shellcheck source=/dev/null
source "$NVM_SH"

if ! command -v nvm >/dev/null 2>&1 && ! type nvm >/dev/null 2>&1; then
  warn "nvm did not load from $NVM_SH"
  exit 0
fi

current_default="$(nvm version default 2>/dev/null || echo "N/A")"

log "Installing latest Node via nvm"
if ! nvm install node; then
  warn "nvm install node failed"
  exit 0
fi

nvm alias default node >/dev/null 2>&1 || warn "could not set nvm default alias"
nvm use default >/dev/null 2>&1 || true

new_default="$(nvm version default 2>/dev/null || echo "N/A")"
if [[ "$current_default" == "$new_default" ]]; then
  log "Node already current: $new_default"
else
  log "Node default: $current_default -> $new_default"
fi

if command -v node >/dev/null 2>&1; then
  log "node $(node --version), npm $(npm --version 2>/dev/null || echo '?')"
fi
