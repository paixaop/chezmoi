#!/usr/bin/env bash
# Fixture tests for the filter patterns used by scripts/remove-nix.sh.
# Does not touch the real system — only temporary files.

set -euo pipefail

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FAILURES=0
pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*"; FAILURES=$((FAILURES+1)); }

filter() {
  local pattern="$1" file="$2"
  grep -Ev "$pattern" "$file" || true
}

# synthetic.conf: drop bare `nix`, keep `run`
cat > "$TMP/synthetic.conf" <<'EOF'

nix
run	private/var/run
EOF
out="$(filter '^[[:space:]]*nix([[:space:]]|$)' "$TMP/synthetic.conf")"
if printf '%s\n' "$out" | grep -q 'private/var/run' \
   && ! printf '%s\n' "$out" | grep -Eq '^[[:space:]]*nix([[:space:]]|$)'; then
  pass "synthetic.conf keeps run, drops nix"
else
  fail "synthetic.conf filter wrong: [$out]"
fi

# fstab: drop Determinate /nix line, keep unrelated entries
cat > "$TMP/fstab" <<'EOF'
# header
UUID=abc /nix apfs rw,noatime,noauto,nobrowse,nosuid,owners # Added by the Determinate Nix Installer
UUID=def /other apfs rw
EOF
out="$(filter '[[:space:]]/nix[[:space:]]|Determinate Nix|/nix apfs' "$TMP/fstab")"
if printf '%s\n' "$out" | grep -q '/other' \
   && ! printf '%s\n' "$out" | grep -q '/nix'; then
  pass "fstab drops /nix, keeps other mounts"
else
  fail "fstab filter wrong: [$out]"
fi

# shell stanza stripping
cat > "$TMP/bashrc" <<'EOF'
# Nix
if [ -e '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' ]; then
    . '/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh'
fi
export FOO=bar
EOF
sed -i '' \
  -e '/nix-daemon\.sh/d' \
  -e '/\/nix\//d' \
  -e '/^# Nix$/d' \
  "$TMP/bashrc"
if grep -q 'FOO=bar' "$TMP/bashrc" && ! grep -Eq 'nix|Nix' "$TMP/bashrc"; then
  pass "shell stanza strip leaves unrelated exports"
else
  fail "shell stanza strip wrong: $(cat "$TMP/bashrc")"
fi

# user rc stripping (hm-session-vars + store source)
cat > "$TMP/profile" <<'EOF'
. "/nix/store/abcd-hm-session-vars.sh/etc/profile.d/hm-session-vars.sh"
export PATH="/usr/bin"
source /nix/store/zzzz/etc/profile.d/nix.sh
EOF
sed -i '' \
  -e '/hm-session-vars/d' \
  -e '/\/nix\/store\//d' \
  -e '/nix-daemon\.sh/d' \
  -e '/^[[:space:]]*\.[[:space:]]*".*nix.*"/d' \
  -e '/^[[:space:]]*source[[:space:]]*.*nix/d' \
  "$TMP/profile"
if grep -q 'PATH=' "$TMP/profile" && ! grep -Eq 'nix|hm-session' "$TMP/profile"; then
  pass "user rc strip removes hm-session-vars and store sources"
else
  fail "user rc strip wrong: $(cat "$TMP/profile")"
fi

# backup name preference order
touch "$TMP/zshrc.before-nix-darwin"
touch "$TMP/zshrc.backup-before-nix"
chosen=""
for backup in \
    "$TMP/zshrc.backup-before-nix-darwin" \
    "$TMP/zshrc.before-nix-darwin" \
    "$TMP/zshrc.backup-before-nix" \
    "$TMP/zshrc.before-nix"; do
  if [[ -f "$backup" ]]; then chosen="$backup"; break; fi
done
if [[ "$chosen" == "$TMP/zshrc.before-nix-darwin" ]]; then
  pass "prefers .before-nix-darwin over .backup-before-nix"
else
  fail "backup preference wrong: $chosen"
fi

if [[ "$FAILURES" -eq 0 ]]; then
  printf '==> remove-nix filter tests passed\n'
else
  printf '==> remove-nix filter tests failed: %s\n' "$FAILURES" >&2
  exit 1
fi
