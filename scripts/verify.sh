#!/usr/bin/env bash
# Local and CI verification for this chezmoi source tree.
# Read-only: renders templates into a temporary directory and never applies.
#
# Usage:
#   scripts/verify.sh          # full run
#   CI=1 scripts/verify.sh     # skip checks that need machine-local data

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SOURCE_DIR"

PASS=0
FAILED=0
SKIPPED=0

ok()      { printf '  ok    %s\n' "$*"; PASS=$((PASS+1)); }
bad()     { printf '  FAIL  %s\n' "$*"; FAILED=$((FAILED+1)); }
skipped() { printf '  skip  %s\n' "$*"; SKIPPED=$((SKIPPED+1)); }
section() { printf '\n==> %s\n' "$*"; }

have() { command -v "$1" >/dev/null 2>&1; }

RENDER_DIR="$(mktemp -d)"
trap 'rm -rf "$RENDER_DIR"' EXIT

# Templates need data. Use the machine config when present, otherwise feed
# chezmoi deterministic values so CI can still render every template.
CHEZMOI_ARGS=(--source="$SOURCE_DIR")
if [[ -f "$SOURCE_DIR/chezmoi.toml" ]]; then
  CHEZMOI_ARGS+=(--config="$SOURCE_DIR/chezmoi.toml")
else
  cat > "$RENDER_DIR/config.toml" <<'EOF'
[data]
    name = "Verify Fixture"
    email = "verify@example.com"
    workEmail = "verify-work@example.com"
    personalEmail = "verify-personal@example.com"
    hostname = "verify-host"
    timezone = "America/New_York"
    username = "verify"
[data.policy]
    firewallEnabled = true
    firewallStealthMode = true
    firewallBlockAll = false
EOF
  CHEZMOI_ARGS+=(--config="$RENDER_DIR/config.toml")
fi

section "Required tooling"
for cmd in chezmoi shellcheck python3; do
  if have "$cmd"; then
    ok "$cmd available"
  else
    bad "$cmd not found"
  fi
done
if [[ "$FAILED" -gt 0 ]]; then
  printf '\nInstall missing tools first: brew bundle install --file=%s/Brewfile\n' "$SOURCE_DIR" >&2
  exit 1
fi

section "Template rendering"
# Built for macOS's bash 3.2: no mapfile, no associative arrays.
TEMPLATES=()
while IFS= read -r line; do
  TEMPLATES+=("$line")
done < <(find . -name '*.tmpl' -not -path './.git/*' | sort)
CONFIG_PROMPTS="full name=Verify Fixture,primary email=verify@example.com"
CONFIG_PROMPTS="$CONFIG_PROMPTS,work git email=verify-work@example.com"
CONFIG_PROMPTS="$CONFIG_PROMPTS,personal git email=verify-personal@example.com"
CONFIG_PROMPTS="$CONFIG_PROMPTS,hostname=verify-host,timezone=America/New_York"

for tmpl in "${TEMPLATES[@]}"; do
  rel="${tmpl#./}"
  out="$RENDER_DIR/${rel//\//__}"
  out="${out%.tmpl}"
  # The config template uses promptString, which only exists during init.
  if [[ "$rel" == ".chezmoi.toml.tmpl" ]]; then
    if chezmoi "${CHEZMOI_ARGS[@]}" execute-template --init \
        --promptString "$CONFIG_PROMPTS" < "$tmpl" > "$out" 2>"$out.err"; then
      ok "rendered $rel"
    else
      bad "render failed: $rel"
      sed 's/^/        /' "$out.err" >&2
    fi
    continue
  fi
  if chezmoi "${CHEZMOI_ARGS[@]}" execute-template < "$tmpl" > "$out" 2>"$out.err"; then
    ok "rendered $rel"
  else
    bad "render failed: $rel"
    sed 's/^/        /' "$out.err" >&2
  fi
done

section "ShellCheck"
SHELL_SOURCES=()
while IFS= read -r line; do
  SHELL_SOURCES+=("$line")
done < <(find . -name '*.sh' -not -path './.git/*' | sort)
for script in "${SHELL_SOURCES[@]}"; do
  if shellcheck --external-sources --source-path="$SOURCE_DIR" "$script" >/dev/null 2>"$RENDER_DIR/sc.err"; then
    ok "shellcheck ${script#./}"
  else
    bad "shellcheck ${script#./}"
    shellcheck --external-sources --source-path="$SOURCE_DIR" "$script" | sed 's/^/        /' >&2 || true
  fi
done

# Rendered *.sh.tmpl output is what actually runs on the machine.
for rendered in "$RENDER_DIR"/*.sh; do
  [[ -e "$rendered" ]] || continue
  name="$(basename "$rendered")"
  if shellcheck --shell=bash --exclude=SC1091 "$rendered" >/dev/null 2>&1; then
    ok "shellcheck rendered $name"
  else
    bad "shellcheck rendered $name"
    shellcheck --shell=bash --exclude=SC1091 "$rendered" | sed 's/^/        /' >&2 || true
  fi
done

section "Syntax checks"
for py in scripts/*.py; do
  [[ -e "$py" ]] || continue
  if python3 -m py_compile "$py" 2>"$RENDER_DIR/py.err"; then
    ok "python syntax $py"
  else
    bad "python syntax $py"
    sed 's/^/        /' "$RENDER_DIR/py.err" >&2
  fi
done
rm -rf scripts/__pycache__

if have python3; then
  for toml in dot_config/mise/config.toml dot_cargo/config.toml; do
    [[ -f "$toml" ]] || continue
    if python3 -c "import tomllib,sys; tomllib.load(open(sys.argv[1],'rb'))" "$toml" 2>/dev/null; then
      ok "toml syntax $toml"
    else
      bad "toml syntax $toml"
    fi
  done
fi

section "Unit tests"
if [[ -x scripts/test-dock-merge.py ]]; then
  if python3 scripts/test-dock-merge.py >/dev/null 2>"$RENDER_DIR/dock.err"; then
    ok "dock merge tests"
  else
    bad "dock merge tests"
    sed 's/^/        /' "$RENDER_DIR/dock.err" >&2
  fi
fi

if [[ -x scripts/test-postflight.sh ]]; then
  if ./scripts/test-postflight.sh >"$RENDER_DIR/postflight.out" 2>&1; then
    ok "postflight fatal/warn tests"
  else
    bad "postflight fatal/warn tests"
    sed 's/^/        /' "$RENDER_DIR/postflight.out" >&2
  fi
fi

section "chezmoi state"
if [[ -f "$SOURCE_DIR/chezmoi.toml" ]]; then
  if chezmoi "${CHEZMOI_ARGS[@]}" verify >/dev/null 2>&1; then
    ok "chezmoi verify (target matches source)"
  else
    printf '  note  chezmoi verify reports pending changes:\n'
    chezmoi "${CHEZMOI_ARGS[@]}" diff --no-pager 2>/dev/null | sed 's/^/        /' | head -40 || true
    ok "chezmoi diff readable"
  fi
else
  skipped "chezmoi verify (no machine config; run chezmoi init)"
fi

section "Homebrew"
if have brew; then
  if brew bundle check --file="$SOURCE_DIR/Brewfile" >/dev/null 2>&1; then
    ok "Brewfile dependencies satisfied"
  else
    printf '  note  missing Brewfile dependencies:\n'
    brew bundle check --file="$SOURCE_DIR/Brewfile" --verbose 2>&1 | sed 's/^/        /' | head -20 || true
    ok "Brewfile parsed"
  fi
else
  skipped "brew bundle check (Homebrew not installed)"
fi

printf '\n==> verify: %s ok, %s failed, %s skipped\n' "$PASS" "$FAILED" "$SKIPPED"
[[ "$FAILED" -eq 0 ]]
