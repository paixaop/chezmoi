#!/usr/bin/env bash
# Regression tests for the Nix-to-Homebrew migration contract.

set -euo pipefail

SOURCE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$SOURCE_DIR/scripts/prepare-nix-exit.sh"
BREWFILE="$SOURCE_DIR/Brewfile"
BREW_STAGE="$SOURCE_DIR/run_onchange_before_10-homebrew.sh.tmpl"
FAILURES=0

pass() { printf '  ok    %s\n' "$*"; }
fail() { printf '  FAIL  %s\n' "$*" >&2; FAILURES=$((FAILURES + 1)); }

expect_contains() {
  local file="$1" pattern="$2" description="$3"
  if grep -Eq "$pattern" "$file"; then pass "$description"; else fail "$description"; fi
}

expect_absent() {
  local file="$1" pattern="$2" description="$3"
  if grep -Eq "$pattern" "$file"; then fail "$description"; else pass "$description"; fi
}

expect_contains "$SCRIPT" 'origin main' \
  "restores Homebrew from its canonical main branch"
expect_absent "$SCRIPT" 'brew bundle install' \
  "migration does not install the unrelated full Brewfile"

for formula in chezmoi git gh tmux neovim mise uv direnv; do
  expect_contains "$SCRIPT" "^[[:space:]]+${formula}$" \
    "migration installs formula: $formula"
done

expect_absent "$BREWFILE" '^brew "codex"$' \
  "Codex is not declared as a formula"
expect_absent "$BREWFILE" '^brew "claude-code"$' \
  "Claude Code is not declared as a formula"
expect_absent "$BREWFILE" '^brew "mitmproxy"$' \
  "mitmproxy is not declared as a formula"
expect_contains "$BREWFILE" '^cask "codex"$' \
  "Codex is declared as a cask"
expect_contains "$BREWFILE" '^cask "claude-code"$' \
  "Claude Code is declared as a cask"
expect_contains "$BREWFILE" '^cask "mitmproxy"$' \
  "mitmproxy is declared as a cask"

for tap in hashicorp joshavant cirruslabs mutagen-io; do
  expect_absent "$BREW_STAGE" "$tap" \
    "Homebrew stage does not restore unused tap: $tap"
done

if [[ "$FAILURES" -gt 0 ]]; then
  printf '==> prepare-nix-exit tests failed: %s\n' "$FAILURES" >&2
  exit 1
fi
printf '==> prepare-nix-exit tests passed\n'
