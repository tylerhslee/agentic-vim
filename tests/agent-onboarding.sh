#!/usr/bin/env bash
# Verifies the repository metadata a newly started coding agent relies on.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
LIVE=0

case "${1:-}" in
  "") ;;
  --live) LIVE=1 ;;
  *) printf 'Usage: %s [--live]\n' "$0" >&2; exit 2 ;;
esac

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

[[ -f "$ROOT/AGENTS.md" ]] || fail "AGENTS.md is missing"
[[ -f "$ROOT/CLAUDE.md" ]] || fail "CLAUDE.md is missing"
[[ -f "$ROOT/LICENSE" ]] || fail "project license is missing"
[[ -f "$ROOT/THIRD_PARTY_NOTICES.md" ]] || fail "third-party notices are missing"

grep -Fxq '@AGENTS.md' "$ROOT/CLAUDE.md" \
  || fail "CLAUDE.md does not import the canonical AGENTS.md guide"
grep -Fq 'Verification ladder' "$ROOT/AGENTS.md" \
  || fail "the contributor guide does not document verification"
grep -Fq 'carlos-algms/agentic.nvim' "$ROOT/AGENTS.md" \
  || fail "the contributor guide omits Agentic.nvim provenance"
grep -Fq 'Carlos Gomes' "$ROOT/THIRD_PARTY_NOTICES.md" \
  || fail "Agentic.nvim attribution is missing"

dry_run=$("$ROOT/scripts/install.sh" --dry-run)
grep -Fq '/agentic-vim' <<<"$dry_run" \
  || fail "installer dry-run omits the isolated application namespace"
grep -Fq 'without changing ~/.config/nvim' <<<"$dry_run" \
  || fail "installer dry-run does not promise Neovim config isolation"
grep -Fq '/nvim.' <<<"$dry_run" \
  || fail "installer dry-run omits the nvim launcher"

if command -v claude >/dev/null 2>&1; then
  claude --version >/dev/null \
    || fail "the installed Claude Code CLI cannot report its version"
  printf 'PASS: Claude Code CLI is available for optional live onboarding\n'
else
  printf 'SKIP: Claude Code CLI is not installed; static onboarding contract verified\n'
fi

printf 'PASS: Claude Code project instructions and publication metadata verified\n'

if ((LIVE)); then
  command -v claude >/dev/null 2>&1 \
    || fail "--live requires the Claude Code CLI"
  prompt='Read the project instructions without modifying files. Reply with exactly two lines: first, the project name; second, the documented command that verifies coding-agent onboarding.'
  if ! response=$(claude -p --permission-mode plan --tools '' \
      --no-session-persistence --init "$prompt"); then
    fail "live Claude onboarding failed; verify authentication with: claude auth status"
  fi
  grep -Fqi 'Agentic Vim' <<<"$response" \
    || fail "live Claude response did not identify Agentic Vim"
  grep -Fq 'bash tests/agent-onboarding.sh' <<<"$response" \
    || fail "live Claude response did not recover the onboarding check"
  printf 'PASS: live Claude Code onboarding loaded the project instructions\n'
fi
