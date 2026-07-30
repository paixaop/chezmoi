#!/usr/bin/env bash
# Tests for path_is_nix in lib/common.sh.
#
# Regression: nix-darwin exposes binaries via /etc/profiles/per-user/<user>,
# which resolves through /etc/static into /nix/store. The original check only
# matched literal /nix and /run/current-system prefixes, so those tools were
# reported as safe and remove-nix.sh would have deleted a live toolchain.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=/dev/null
source "$SOURCE_DIR/lib/common.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILURES=0
pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILURES=$((FAILURES+1)); }

expect_nix() {
  if path_is_nix "$1"; then pass "detects Nix: $2"; else fail "missed Nix path: $1 ($2)"; fi
}
expect_clean() {
  if path_is_nix "$1"; then fail "false positive: $1 ($2)"; else pass "allows: $2"; fi
}

# Literal prefixes
expect_nix /nix/store/abc-git-2.54.0/bin/git "literal /nix/store"
expect_nix /run/current-system/sw/bin/gh "literal /run/current-system"
expect_nix /etc/profiles/per-user/pedro/bin/git "nix-darwin per-user profile"
expect_nix /etc/static/bashrc "nix-darwin /etc/static"

# Non-Nix paths
expect_clean /usr/bin/git "system git"
expect_clean /usr/local/bin/something "usr local bin"

# Symlink chain resolution: a harmless-looking path whose target is in the store.
# This is the case the original implementation missed.
mkdir -p "$TMP/nix/store/xyz-tool/bin" "$TMP/etcish"
printf '#!/bin/sh\n' > "$TMP/nix/store/xyz-tool/bin/tool"
chmod +x "$TMP/nix/store/xyz-tool/bin/tool"
ln -s "$TMP/nix/store/xyz-tool" "$TMP/etcish/profile"

REAL_TMP="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$TMP")"
resolved="$(python3 -c 'import os,sys; print(os.path.realpath(sys.argv[1]))' "$TMP/etcish/profile/bin/tool")"
if [[ "$resolved" == "$REAL_TMP/nix/store/xyz-tool/bin/tool" ]]; then
  pass "symlink chain resolves through to the real store path"
else
  fail "symlink chain did not resolve: $resolved"
fi

# Real-world regression: Homebrew's launcher is a symlink into the store under
# nix-homebrew, so a /opt/homebrew path is NOT automatically safe.
mkdir -p "$TMP/fakebrew/bin"
ln -s "$TMP/nix/store/xyz-tool/bin/tool" "$TMP/fakebrew/bin/brew"
if path_is_nix "$TMP/fakebrew/bin/brew"; then
  fail "unexpected: temp store path matched the production /nix prefix"
else
  pass "temp fixture is outside the real /nix prefix, as expected"
fi

# Nonexistent paths must not crash and must still match on prefix.
expect_nix /nix/store/does-not-exist/bin/nope "nonexistent /nix path"
expect_clean /opt/homebrew/bin/does-not-exist "nonexistent homebrew path"

if [[ "$FAILURES" -eq 0 ]]; then
  printf '==> path_is_nix tests passed\n'
else
  printf '==> path_is_nix tests failed: %s\n' "$FAILURES" >&2
  exit 1
fi
