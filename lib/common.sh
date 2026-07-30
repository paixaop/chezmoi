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

# Guarantee the standard macOS directories are on PATH. Normally /etc/zprofile
# runs path_helper to do this, but that file is a nix-darwin symlink and does
# not survive Nix removal, which silently drops /usr/sbin and /sbin and breaks
# scutil, systemsetup, and friends (including under sudo).
ensure_system_path() {
  local d
  for d in /usr/bin /bin /usr/sbin /sbin; do
    case ":$PATH:" in
      *":$d:"*) ;;
      *) PATH="$PATH:$d" ;;
    esac
  done
  export PATH
}
ensure_system_path

ensure_brew() {
  if ! command -v brew >/dev/null 2>&1 && [[ ! -x /opt/homebrew/bin/brew ]]; then
    log "Homebrew not found; installing"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  fi
  if [[ -x /opt/homebrew/bin/brew ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi
  command -v brew >/dev/null 2>&1 || die "Homebrew install failed; brew still not on PATH"
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
  local p="$1" real=""
  # nix-darwin exposes tools through symlink farms whose names look harmless
  # (/etc/profiles/per-user/... -> /etc/static -> /nix/store/...), so resolve
  # the path before judging it.
  if [[ -e "$p" ]]; then
    real="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$p" 2>/dev/null || true)"
  fi
  local candidate
  for candidate in "$p" "$real"; do
    [[ -n "$candidate" ]] || continue
    case "$candidate" in
      /nix/*|/run/current-system/*|/etc/profiles/*|/etc/static/*)
        return 0
        ;;
    esac
  done
  return 1
}

command_path() {
  command -v "$1" 2>/dev/null || true
}
