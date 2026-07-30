#!/usr/bin/env bash
# Checks that postflight treats missing tools as fatal and drift as a warning.
# Runs against the rendered script with stubbed commands; the host is untouched.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILURES=0

pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILURES=$((FAILURES+1)); }

cat > "$TMP/config.toml" <<'EOF'
[data]
    name = "Verify Fixture"
    email = "verify@example.com"
    workEmail = ""
    personalEmail = "verify@example.com"
    hostname = "verify-host"
    timezone = "America/New_York"
    username = "verify"
[data.policy]
    firewallEnabled = true
    firewallStealthMode = true
    firewallBlockAll = false
EOF

chezmoi --source="$SOURCE_DIR" --config="$TMP/config.toml" execute-template \
  < "$SOURCE_DIR/run_after_90-postflight.sh.tmpl" > "$TMP/postflight.sh"
chmod +x "$TMP/postflight.sh"

# Stub directory: every required tool resolves here, nothing touches the host.
STUB="$TMP/stub"
mkdir -p "$STUB"
for c in brew chezmoi mise uv direnv git gh tmux nvim zsh fzf rg fd \
         defaults scutil sudo awk grep killall; do
  printf '#!/bin/sh\nexit 0\n' > "$STUB/$c"
  chmod +x "$STUB/$c"
done
# Drift on every non-tool check: wrong hostname, no firewall data, no PAM file.
printf '#!/bin/sh\necho other-host\n' > "$STUB/scutil"
chmod +x "$STUB/scutil"
printf '#!/bin/sh\necho 0\n' > "$STUB/defaults"
chmod +x "$STUB/defaults"

run_postflight() {
  env -i PATH="$STUB:/usr/bin:/bin" HOME="$TMP/home" \
    bash "$TMP/postflight.sh" 2>&1
}

mkdir -p "$TMP/home"

set +e
output="$(run_postflight)"
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  pass "drift alone exits 0"
else
  fail "drift alone exited $rc"
  printf '%s\n' "$output" | sed 's/^/        /'
fi

if grep -q 'WARN' <<<"$output"; then
  pass "drift is reported as WARN"
else
  fail "expected WARN lines for drift"
fi

# Remove a required tool: that must be fatal.
rm -f "$STUB/rg"
set +e
output_missing="$(run_postflight)"
rc_missing=$?
set -e

if [[ "$rc_missing" -ne 0 ]]; then
  pass "missing required tool exits non-zero"
else
  fail "missing required tool still exited 0"
fi

if grep -q 'rg not found' <<<"$output_missing"; then
  pass "missing tool is named in output"
else
  fail "expected 'rg not found' in output"
fi

if [[ "$FAILURES" -eq 0 ]]; then
  printf '==> postflight tests passed\n'
else
  printf '==> postflight tests failed: %s\n' "$FAILURES" >&2
  exit 1
fi
