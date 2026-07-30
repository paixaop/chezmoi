#!/usr/bin/env bash
# Tests for scripts/ensure-home-python-env.sh using a fake HOME and stubs.
# The real host home directory is never touched.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILURES=0
pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILURES=$((FAILURES+1)); }

# --- helpers ---------------------------------------------------------------

setup_stubs() {
  local stub="$1"
  mkdir -p "$stub"
  cat > "$stub/mise" <<'EOF'
#!/bin/sh
# Accept install / use without doing anything real.
exit 0
EOF
  cat > "$stub/direnv" <<'EOF'
#!/usr/bin/env bash
case "$1" in
  allow) exit 0 ;;
  exec)
    # Simulate layout python creating ~/.direnv/python3.14
    root="$2"
    shift 2
    venv="$root/.direnv/python3.14"
    mkdir -p "$venv/bin"
    printf '#!/bin/sh\necho Python 3.14.0\n' > "$venv/bin/python"
    chmod +x "$venv/bin/python"
    printf '#!/bin/sh\nexit 0\n' > "$venv/bin/pip"
    chmod +x "$venv/bin/pip"
    if [[ "${1:-}" == "true" ]]; then
      exit 0
    fi
    export VIRTUAL_ENV="$venv"
    export PATH="$venv/bin:$PATH"
    exec "$@"
    ;;
  *) exit 0 ;;
esac
EOF
  cat > "$stub/uv" <<'EOF'
#!/bin/sh
exit 0
EOF
  cat > "$stub/brew" <<'EOF'
#!/bin/sh
# brew shellenv is eval'd; emit nothing so PATH stays on our stubs.
exit 0
EOF
  chmod +x "$stub"/*
}

run_ensure() {
  local home="$1"
  env -i \
    HOME="$home" \
    PATH="$TMP/stub:/usr/bin:/bin" \
    bash "$SOURCE_DIR/scripts/ensure-home-python-env.sh" 3.14
}

# --- cases -----------------------------------------------------------------

STUB="$TMP/stub"
setup_stubs "$STUB"

# 1. Missing .envrc and venv → both created
HOME1="$TMP/home1"
mkdir -p "$HOME1"
run_ensure "$HOME1" >/dev/null
if [[ -f "$HOME1/.envrc" ]] && grep -q 'layout python python3.14' "$HOME1/.envrc" \
   && [[ -x "$HOME1/.direnv/python3.14/bin/python" ]]; then
  pass "creates .envrc and python3.14 venv when missing"
else
  fail "did not create .envrc + venv"
  find "$HOME1" -print | sed 's/^/        /' || true
fi

# 2. Existing .envrc with python3.14 layout, missing venv → creates venv only
HOME2="$TMP/home2"
mkdir -p "$HOME2"
printf 'use mise\nlayout python python3.14\n' > "$HOME2/.envrc"
run_ensure "$HOME2" >/dev/null
if [[ -x "$HOME2/.direnv/python3.14/bin/python" ]]; then
  pass "creates venv when .envrc already declares python3.14"
else
  fail "did not create venv for existing .envrc"
fi

# 3. Custom .envrc without python3.14 → leave alone, no venv
HOME3="$TMP/home3"
mkdir -p "$HOME3"
printf 'export FOO=bar\n' > "$HOME3/.envrc"
before="$(cat "$HOME3/.envrc")"
run_ensure "$HOME3" >/dev/null
after="$(cat "$HOME3/.envrc")"
if [[ "$before" == "$after" && ! -d "$HOME3/.direnv" ]]; then
  pass "leaves custom .envrc alone"
else
  fail "mutated custom .envrc or created unexpected venv"
fi

# 4. Already present → no-op (idempotent)
HOME4="$TMP/home4"
mkdir -p "$HOME4/.direnv/python3.14/bin"
printf 'use mise\nlayout python python3.14\n' > "$HOME4/.envrc"
printf '#!/bin/sh\necho Python 3.14.0\n' > "$HOME4/.direnv/python3.14/bin/python"
chmod +x "$HOME4/.direnv/python3.14/bin/python"
# Make direnv fail if called with exec — should not be needed when venv exists.
cat > "$STUB/direnv" <<'EOF'
#!/bin/sh
case "$1" in
  allow) exit 0 ;;
  exec) echo "direnv exec should not run when venv exists" >&2; exit 1 ;;
  *) exit 0 ;;
esac
EOF
chmod +x "$STUB/direnv"
if run_ensure "$HOME4" >/dev/null; then
  pass "skips recreation when venv already exists"
else
  fail "tried to recreate an existing venv"
fi

if [[ "$FAILURES" -eq 0 ]]; then
  printf '==> ensure-home-python-env tests passed\n'
else
  printf '==> ensure-home-python-env tests failed: %s\n' "$FAILURES" >&2
  exit 1
fi
