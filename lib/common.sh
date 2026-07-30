#!/usr/bin/env bash
# Shared helpers for chezmoi run scripts. Source with:
#   # shellcheck source=/dev/null
#   source "{{ .chezmoi.sourceDir }}/lib/common.sh"

set -euo pipefail

log()  { printf '==> %s\n' "$*"; }
warn() { printf '!!  %s\n' "$*" >&2; }
die()  { printf 'ERROR: %s\n' "$*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "required command not found: $1"
}

ensure_brew() {
  if ! command -v brew >/dev/null 2>&1; then
    die "Homebrew is not installed. Run bootstrap.sh first."
  fi
  eval "$(/opt/homebrew/bin/brew shellenv)"
}

defaults_write_if_changed() {
  # usage: defaults_write_if_changed DOMAIN KEY TYPE VALUE
  # Returns 0 when the value was written, 1 when it already matched.
  local domain="$1" key="$2" type="$3" value="$4"
  local current="" expected="$value"
  current="$(defaults read "$domain" "$key" 2>/dev/null || true)"

  # `defaults read` reports booleans as 1/0, so compare in that form.
  if [[ "$type" == "-bool" ]]; then
    case "$value" in
      true|yes|1)  expected=1 ;;
      false|no|0)  expected=0 ;;
    esac
  fi

  if [[ -n "$current" && "$current" == "$expected" ]]; then
    return 1
  fi

  defaults write "$domain" "$key" "$type" "$value"
  log "defaults: $domain $key = $value"
  return 0
}

sudo_keep() {
  if [[ "$(id -u)" -eq 0 ]]; then
    "$@"
    return
  fi
  sudo -v
  "$@"
}

path_is_nix() {
  local p="$1"
  [[ "$p" == /nix/* || "$p" == /run/current-system/* ]]
}

command_path() {
  command -v "$1" 2>/dev/null || true
}
