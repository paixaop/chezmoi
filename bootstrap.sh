#!/usr/bin/env bash
# Bootstrap macOS from this chezmoi source.
# Usage:
#   ./bootstrap.sh
#   CHEZMOI_REPO=https://github.com/paixaop/chezmoi.git ./bootstrap.sh

set -euo pipefail

SOURCE_DIR="${CHEZMOI_SOURCE_DIR:-$HOME/.config/chezmoi}"
REPO_URL="${CHEZMOI_REPO:-https://github.com/paixaop/chezmoi.git}"

log() { printf '==> %s\n' "$*"; }
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

if [[ "$(uname -s)" != "Darwin" ]]; then
  die "This bootstrap supports macOS only."
fi

if [[ "$(uname -m)" != "arm64" ]]; then
  die "This bootstrap expects Apple Silicon (arm64)."
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Prefer existing checkout when bootstrap lives inside the source tree.
if [[ -f "$SCRIPT_DIR/.chezmoi.toml.tmpl" || -f "$SCRIPT_DIR/Brewfile" ]]; then
  SOURCE_DIR="$SCRIPT_DIR"
fi

if [[ ! -d "$SOURCE_DIR" ]] || [[ ! -f "$SOURCE_DIR/Brewfile" ]]; then
  [[ -n "$REPO_URL" ]] || die "Source missing at $SOURCE_DIR. Set CHEZMOI_REPO to clone it."
  log "Source missing at $SOURCE_DIR"
  log "Cloning $REPO_URL → $SOURCE_DIR"
  mkdir -p "$(dirname "$SOURCE_DIR")"
  git clone "$REPO_URL" "$SOURCE_DIR"
fi

cd "$SOURCE_DIR"

if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

eval "$(/opt/homebrew/bin/brew shellenv)"

if ! command -v chezmoi >/dev/null 2>&1; then
  log "Installing chezmoi"
  brew install chezmoi
fi

export PATH="/opt/homebrew/bin:$PATH"

log "Initializing chezmoi data (interactive prompts once)"
if [[ ! -f "$SOURCE_DIR/chezmoi.toml" ]]; then
  chezmoi init --source="$SOURCE_DIR" --prompt
else
  log "Found existing $SOURCE_DIR/chezmoi.toml; skipping prompts"
fi

log "Pending changes"
chezmoi --source="$SOURCE_DIR" diff || true

log "Applying configuration from $SOURCE_DIR"
chezmoi --source="$SOURCE_DIR" apply --verbose

log "Bootstrap complete."
log "Review postflight output above. Nix was NOT removed."
log "When ready: $SOURCE_DIR/scripts/remove-nix.sh"
