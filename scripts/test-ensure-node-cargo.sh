#!/usr/bin/env bash
# Tests for scripts/ensure-node-nvm.sh and scripts/ensure-cargo-packages.sh.
# Both run against stubs in a fake HOME; no toolchains are installed.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILURES=0
pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILURES=$((FAILURES+1)); }

STUB="$TMP/stub"
mkdir -p "$STUB"
cat > "$STUB/brew" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$STUB/brew"

# --- ensure-node-nvm.sh ----------------------------------------------------

# Fake nvm.sh defining an nvm shell function, recording calls.
cat > "$TMP/nvm.sh" <<'EOF'
nvm() {
  echo "nvm $*" >> "$NVM_LOG"
  case "$1 $2" in
    "version default") echo "v24.0.0" ;;
  esac
  return 0
}
EOF

run_node() {
  local home="$1"
  env -i \
    HOME="$home" \
    PATH="$STUB:/usr/bin:/bin" \
    NVM_SH_OVERRIDE="$TMP/nvm.sh" \
    NVM_DIR="$home/.nvm" \
    NVM_LOG="$TMP/nvm.log" \
    bash "$SOURCE_DIR/scripts/ensure-node-nvm.sh"
}

# 1. Installs node and sets the default alias.
HOME1="$TMP/home1"
mkdir -p "$HOME1"
: > "$TMP/nvm.log"
run_node "$HOME1" >/dev/null
if grep -q 'nvm install node' "$TMP/nvm.log" && grep -q 'nvm alias default node' "$TMP/nvm.log"; then
  pass "nvm installs node and sets default"
else
  fail "expected nvm install + alias, got: $(tr '\n' ';' < "$TMP/nvm.log")"
fi

# 2. An npm prefix (which breaks nvm) is removed and backed up.
HOME2="$TMP/home2"
mkdir -p "$HOME2"
printf 'prefix=/Users/x/.npm-global\nignore-scripts=false\n' > "$HOME2/.npmrc"
: > "$TMP/nvm.log"
run_node "$HOME2" >/dev/null 2>&1
if ! grep -q '^prefix=' "$HOME2/.npmrc" \
   && grep -q 'ignore-scripts=false' "$HOME2/.npmrc" \
   && compgen -G "$HOME2/.npmrc.bak.*" >/dev/null; then
  pass "removes npm prefix and keeps a backup"
else
  fail "npmrc prefix not handled: $(cat "$HOME2/.npmrc")"
fi

# 3. Missing nvm is tolerated.
HOME3="$TMP/home3"
mkdir -p "$HOME3"
if env -i HOME="$HOME3" PATH="$STUB:/usr/bin:/bin" \
     NVM_SH_OVERRIDE="$TMP/absent.sh" \
     bash "$SOURCE_DIR/scripts/ensure-node-nvm.sh" >/dev/null 2>&1; then
  pass "missing nvm exits 0"
else
  fail "missing nvm failed the run"
fi

# --- ensure-cargo-packages.sh ---------------------------------------------

cat > "$STUB/cargo" <<'EOF'
#!/bin/sh
if [ "$1" = "install" ] && [ "$2" = "--list" ]; then
  printf 'cargo-watch v8.5.3:\n    cargo-watch\nsqlx-cli v0.8.0:\n    sqlx\n'
  exit 0
fi
if [ "$1" = "binstall" ]; then
  shift
  echo "$*" >> "$CARGO_LOG"
  exit 0
fi
if [ "$1" = "install" ]; then
  shift
  echo "install $*" >> "$CARGO_LOG"
  exit 0
fi
exit 0
EOF
cat > "$STUB/cargo-binstall" <<'EOF'
#!/bin/sh
exit 0
EOF
chmod +x "$STUB/cargo" "$STUB/cargo-binstall"

run_cargo() {
  local list="$1"
  env -i \
    HOME="$TMP/home1" \
    PATH="$STUB:/usr/bin:/bin" \
    CARGO_LOG="$TMP/cargo.log" \
    bash "$SOURCE_DIR/scripts/ensure-cargo-packages.sh" "$list"
}

# 4. Only crates missing from `cargo install --list` are installed.
cat > "$TMP/crates.txt" <<'EOF'
# comment
cargo-watch
sqlx-cli
cargo-expand
EOF
: > "$TMP/cargo.log"
run_cargo "$TMP/crates.txt" >/dev/null
logged="$(cat "$TMP/cargo.log" 2>/dev/null || true)"
if [[ "$logged" == *"cargo-expand"* && "$logged" != *"cargo-watch"* && "$logged" != *"sqlx-cli"* ]]; then
  pass "installs only missing crates"
else
  fail "unexpected crate install set: '$logged'"
fi

# 5. Nothing missing → no install call.
printf 'cargo-watch\nsqlx-cli\n' > "$TMP/crates2.txt"
: > "$TMP/cargo.log"
run_cargo "$TMP/crates2.txt" >/dev/null
if [[ ! -s "$TMP/cargo.log" ]]; then
  pass "no cargo install when all crates present"
else
  fail "ran cargo install unnecessarily: $(cat "$TMP/cargo.log")"
fi

# 6. Missing cargo is tolerated.
NO_CARGO="$TMP/stub-nocargo"
mkdir -p "$NO_CARGO"
cp "$STUB/brew" "$NO_CARGO/brew"
if env -i HOME="$TMP/home1" PATH="$NO_CARGO:/usr/bin:/bin" \
     bash "$SOURCE_DIR/scripts/ensure-cargo-packages.sh" "$TMP/crates.txt" >/dev/null 2>&1; then
  pass "missing cargo exits 0"
else
  fail "missing cargo failed the run"
fi

if [[ "$FAILURES" -eq 0 ]]; then
  printf '==> node/cargo provisioning tests passed\n'
else
  printf '==> node/cargo provisioning tests failed: %s\n' "$FAILURES" >&2
  exit 1
fi
