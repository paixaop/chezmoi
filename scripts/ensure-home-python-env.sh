#!/usr/bin/env bash
# Ensure $HOME has a direnv-managed Python 3.14 environment.
# Idempotent: never overwrites a custom ~/.envrc, and skips when the
# virtualenv already exists under ~/.direnv/python3.14.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SOURCE_DIR/lib/common.sh"

PYVER="${1:-3.14}"
HOME_ENVRC="$HOME/.envrc"
HOME_VENV="$HOME/.direnv/python${PYVER}"
EXPECTED_ENVRC=$'use mise\nlayout python python'"${PYVER}"$'\n'

if command -v brew >/dev/null 2>&1; then
  # Prefer an already-active brew so test stubs on PATH stay first.
  eval "$(brew shellenv 2>/dev/null || true)"
elif [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi
# Append, do not prepend — callers (and tests) may put preferred tools first.
export PATH="${PATH:+$PATH:}/opt/homebrew/bin:${HOME}/.local/bin"

if ! command -v mise >/dev/null 2>&1; then
  warn "mise not found; skipping home Python ${PYVER} env"
  exit 0
fi

if ! command -v direnv >/dev/null 2>&1; then
  warn "direnv not found; skipping home Python ${PYVER} env"
  exit 0
fi

# mise needs the language available before direnv's layout python can wire it.
log "Ensuring Python ${PYVER} via mise"
mise install "python@${PYVER}" -y || warn "mise install python@${PYVER} reported issues"

if [[ -f "$HOME_ENVRC" ]]; then
  if ! grep -Eq "layout[[:space:]]+python[[:space:]]+python${PYVER}" "$HOME_ENVRC"; then
    warn "$HOME_ENVRC exists without a python${PYVER} layout; leaving it alone"
    exit 0
  fi
  log "Found existing $HOME_ENVRC with python${PYVER} layout"
else
  log "Creating $HOME_ENVRC for Python ${PYVER}"
  printf '%s' "$EXPECTED_ENVRC" > "$HOME_ENVRC"
fi

if [[ -d "$HOME_VENV" && -x "$HOME_VENV/bin/python" ]]; then
  log "Home Python ${PYVER} env already present at $HOME_VENV"
  direnv allow "$HOME" >/dev/null 2>&1 || true
  exit 0
fi

log "Creating home Python ${PYVER} env at $HOME_VENV"
direnv allow "$HOME"

# direnv exec runs the layout in a clean subshell, which creates the venv.
if ! direnv exec "$HOME" true; then
  warn "direnv failed to create $HOME_VENV"
  exit 0
fi

if [[ -x "$HOME_VENV/bin/python" ]]; then
  # Match penv: keep pip current inside the new env.
  direnv exec "$HOME" bash -c \
    'command -v uv >/dev/null && uv pip install --upgrade pip || python -m pip install --upgrade pip' \
    || warn "pip upgrade in home env reported issues"
  log "Home Python ${PYVER} env ready: $("$HOME_VENV"/bin/python --version 2>&1)"
else
  warn "Expected $HOME_VENV/bin/python after direnv exec, but it is missing"
fi
