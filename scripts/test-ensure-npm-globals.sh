#!/usr/bin/env bash
# Tests for scripts/ensure-npm-globals.sh using a stubbed npm.
# No packages are installed and the real npm prefix is never touched.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILURES=0
pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILURES=$((FAILURES+1)); }

STUB="$TMP/stub"
mkdir -p "$STUB"

# npm stub: reports typescript + @scope/one as already installed and records
# any install invocation to $TMP/install.log.
cat > "$STUB/npm" <<'EOF'
#!/bin/sh
case "$1 $2" in
  "ls -g")
    cat <<'JSON'
{"dependencies":{"typescript":{"version":"5.9.3"},"@scope/one":{"version":"1.0.0"}}}
JSON
    exit 0
    ;;
esac
if [ "$1" = "install" ]; then
  shift
  echo "$*" >> "$INSTALL_LOG"
  exit 0
fi
exit 0
EOF
cat > "$STUB/brew" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$STUB"/*

run_globals() {
  local list="$1"
  env -i \
    HOME="$TMP/home" \
    PATH="$STUB:/usr/bin:/bin" \
    INSTALL_LOG="$TMP/install.log" \
    bash "$SOURCE_DIR/scripts/ensure-npm-globals.sh" "$list"
}

mkdir -p "$TMP/home"

# 1. Only missing packages are installed; comments/blanks ignored.
cat > "$TMP/list1.txt" <<'EOF'
# a comment
typescript

@scope/one
@scope/two
pyright
EOF
: > "$TMP/install.log"
run_globals "$TMP/list1.txt" >/dev/null
logged="$(cat "$TMP/install.log" 2>/dev/null || true)"
if [[ "$logged" == *"@scope/two"* && "$logged" == *"pyright"* \
      && "$logged" != *"typescript"* && "$logged" != *"@scope/one"* ]]; then
  pass "installs only missing packages"
else
  fail "unexpected install set: '$logged'"
fi

# 2. Nothing missing → no npm install at all.
cat > "$TMP/list2.txt" <<'EOF'
typescript
@scope/one
EOF
: > "$TMP/install.log"
run_globals "$TMP/list2.txt" >/dev/null
if [[ ! -s "$TMP/install.log" ]]; then
  pass "no install when everything is present"
else
  fail "ran install unnecessarily: $(cat "$TMP/install.log")"
fi

# 3. Empty / comment-only list is a no-op.
printf '# nothing here\n\n' > "$TMP/list3.txt"
: > "$TMP/install.log"
if run_globals "$TMP/list3.txt" >/dev/null && [[ ! -s "$TMP/install.log" ]]; then
  pass "empty list is a no-op"
else
  fail "empty list did something"
fi

# 4. Missing list file warns but exits cleanly.
if run_globals "$TMP/does-not-exist.txt" >/dev/null 2>&1; then
  pass "missing list file exits 0"
else
  fail "missing list file failed the run"
fi

# 5. Missing npm is tolerated.
NPM_LESS="$TMP/stub-nonpm"
mkdir -p "$NPM_LESS"
cp "$STUB/brew" "$NPM_LESS/brew"
if env -i HOME="$TMP/home" PATH="$NPM_LESS:/usr/bin:/bin" \
     bash "$SOURCE_DIR/scripts/ensure-npm-globals.sh" "$TMP/list1.txt" >/dev/null 2>&1; then
  pass "missing npm exits 0"
else
  fail "missing npm failed the run"
fi

if [[ "$FAILURES" -eq 0 ]]; then
  printf '==> ensure-npm-globals tests passed\n'
else
  printf '==> ensure-npm-globals tests failed: %s\n' "$FAILURES" >&2
  exit 1
fi
