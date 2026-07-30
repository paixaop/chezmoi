#!/usr/bin/env bash
# Tests for ensure_system_path / ensure_brew_path in lib/common.sh.
#
# Regression: agent / CI shells often skip /etc/zprofile, so path_helper never
# runs and Homebrew stays off PATH even when /etc/paths.d/homebrew exists.
# Scripts that source common.sh must still resolve brew and gh.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

FAILURES=0
pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

path_index() {
  # 1-based index of directory $1 in PATH, or empty if absent.
  local needle="$1" i=0 part
  local IFS=':'
  # shellcheck disable=SC2086
  for part in $PATH; do
    i=$((i + 1))
    if [[ "$part" == "$needle" ]]; then
      printf '%s' "$i"
      return 0
    fi
  done
  return 1
}

# Start from a stripped PATH with no brew, then source common.sh.
export PATH="/usr/bin:/bin"
# shellcheck source=/dev/null
source "$SOURCE_DIR/lib/common.sh"

case ":$PATH:" in
  *:/usr/sbin:*) pass "ensure_system_path adds /usr/sbin" ;;
  *)             fail "ensure_system_path did not add /usr/sbin (PATH=$PATH)" ;;
esac

case ":$PATH:" in
  *:/sbin:*) pass "ensure_system_path adds /sbin" ;;
  *)         fail "ensure_system_path did not add /sbin (PATH=$PATH)" ;;
esac

if [[ -d /opt/homebrew/bin && -x /opt/homebrew/bin/brew ]]; then
  case ":$PATH:" in
    *:/opt/homebrew/bin:*) pass "ensure_brew_path adds /opt/homebrew/bin" ;;
    *) fail "ensure_brew_path did not add /opt/homebrew/bin (PATH=$PATH)" ;;
  esac
  hb_pos="$(path_index /opt/homebrew/bin || true)"
  ub_pos="$(path_index /usr/bin || true)"
  if [[ -n "$hb_pos" && -n "$ub_pos" && "$hb_pos" -lt "$ub_pos" ]]; then
    pass "Homebrew bin precedes /usr/bin"
  else
    fail "Homebrew bin does not precede /usr/bin (PATH=$PATH)"
  fi
else
  pass "skip brew path check (/opt/homebrew/bin/brew absent)"
fi

# Idempotent: a second call must not duplicate entries.
before="$PATH"
ensure_brew_path
ensure_system_path
if [[ "$before" == "$PATH" ]]; then
  pass "second ensure_*_path call is a no-op"
else
  fail "second ensure_*_path call changed PATH"
fi

# Stub brew must win: ensure_brew_path must not prepend the real prefix over it.
STUB="$(mktemp -d)"
trap 'rm -rf "$STUB"' EXIT
printf '#!/bin/sh\nexit 0\n' > "$STUB/brew"
chmod +x "$STUB/brew"
PATH="$STUB:/usr/bin:/bin"
ensure_brew_path
case "$PATH" in
  "$STUB":*) pass "leaves stub brew ahead of real Homebrew" ;;
  *)         fail "prepended real Homebrew over stub (PATH=$PATH)" ;;
esac
if [[ "$(command -v brew)" == "$STUB/brew" ]]; then
  pass "stub brew remains the resolvable brew"
else
  fail "real brew shadowed the stub ($(command -v brew))"
fi

if [[ "$FAILURES" -gt 0 ]]; then
  printf '==> ensure-path tests failed: %s\n' "$FAILURES" >&2
  exit 1
fi
printf '==> ensure-path tests passed\n'
