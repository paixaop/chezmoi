#!/usr/bin/env bash
# Tests for restore-etc-shell-files.sh.
#
# Regression: remove-nix.sh deleted the nix-darwin symlinks at /etc/zprofile,
# /etc/zshrc, and /etc/bashrc without restoring Apple's originals. Losing
# /etc/zprofile means path_helper never runs, so login shells lose /usr/sbin,
# /sbin, and /usr/local/bin from PATH — which is why `sudo scutil` failed.
# Its line-based Nix stripping also left /etc/bash.bashrc with an orphan `fi`.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SOURCE_DIR/scripts/restore-etc-shell-files.sh"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILURES=0
pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

ETC="$TMP/etc"
mkdir -p "$ETC"

# Reproduce the damaged state: the three files are absent, and bash.bashrc has
# been reduced to an orphan `fi` by the sed pass.
printf '\nfi\n# End Nix\n\n' > "$ETC/bash.bashrc"

run_restore() { ETC_DIR="$ETC" NO_SUDO=1 bash "$SCRIPT" >"$TMP/out" 2>&1; }

if run_restore; then
  pass "restore runs cleanly against a damaged /etc"
else
  fail "restore failed"
  sed 's/^/        /' "$TMP/out" >&2
fi

for f in zprofile zshrc bashrc; do
  if [[ -f "$ETC/$f" ]]; then pass "recreated /etc/$f"; else fail "missing /etc/$f"; fi
done

if grep -q 'path_helper' "$ETC/zprofile"; then
  pass "zprofile runs path_helper (restores PATH)"
else
  fail "zprofile does not call path_helper"
fi

# The whole point: a login shell must get /usr/sbin back.
if [[ -f "$ETC/zprofile" ]]; then
  got="$(PATH=/usr/bin:/bin zsh -c "emulate -L sh; . '$ETC/zprofile'; printf '%s' \"\$PATH\"" 2>/dev/null || true)"
  case ":$got:" in
    *:/usr/sbin:*) pass "sourcing zprofile puts /usr/sbin back on PATH" ;;
    *)             fail "sourcing zprofile did not restore /usr/sbin (got: $got)" ;;
  esac
fi

# Apple does not ship /etc/bash.bashrc; the orphan `fi` file must not survive.
if [[ -e "$ETC/bash.bashrc" ]]; then
  if bash -n "$ETC/bash.bashrc" 2>/dev/null; then
    pass "bash.bashrc is syntactically valid"
  else
    fail "bash.bashrc still has a syntax error (orphan fi)"
  fi
else
  pass "removed the orphan-fi bash.bashrc"
fi

for f in zprofile zshrc; do
  if zsh -n "$ETC/$f" 2>/dev/null; then pass "zsh syntax ok: $f"; else fail "zsh syntax error: $f"; fi
done
if bash -n "$ETC/bashrc" 2>/dev/null; then pass "bash syntax ok: bashrc"; else fail "bash syntax error: bashrc"; fi

# Idempotency: a second run must not alter good files.
before="$(cat "$ETC/zprofile")"
run_restore || fail "second run failed"
if [[ "$before" == "$(cat "$ETC/zprofile")" ]]; then
  pass "second run leaves existing files untouched"
else
  fail "second run rewrote zprofile"
fi

# A user-customised file must never be clobbered.
printf '# my own zprofile\nexport CUSTOM=1\n' > "$ETC/zprofile"
run_restore || fail "third run failed"
if grep -q 'CUSTOM=1' "$ETC/zprofile"; then
  pass "does not overwrite an existing customised file"
else
  fail "overwrote a customised zprofile"
fi

if [[ "$FAILURES" -gt 0 ]]; then
  printf '==> restore-etc-shell-files tests failed: %s\n' "$FAILURES" >&2
  exit 1
fi
printf '==> restore-etc-shell-files tests passed\n'
