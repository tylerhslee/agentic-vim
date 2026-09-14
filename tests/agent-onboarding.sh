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
HARNESS_SPEC="$ROOT/docs/architecture/orchestration-harness.md"
UPSTREAM_SPEC="$ROOT/docs/architecture/upstream-strategy.md"
[[ -f "$HARNESS_SPEC" ]] || fail "orchestration harness architecture is missing"
[[ -f "$UPSTREAM_SPEC" ]] || fail "Agentic.nvim upstream strategy is missing"

grep -Fxq '@AGENTS.md' "$ROOT/CLAUDE.md" \
  || fail "CLAUDE.md does not import the canonical AGENTS.md guide"
grep -Fq 'Verification ladder' "$ROOT/AGENTS.md" \
  || fail "the contributor guide does not document verification"
grep -Fq 'capability map' "$ROOT/AGENTS.md" \
  || fail "the contributor guide does not require capability planning"
grep -Fq 'mutually exclusive and collectively exhaustive (MECE)' "$ROOT/AGENTS.md" \
  || fail "the contributor guide does not require MECE capability ownership"
grep -Fq 'Only the integration phase may modify' "$ROOT/AGENTS.md" \
  || fail "the contributor guide does not protect the canonical working tree"
grep -Fq 'Review the combined result adversarially' "$ROOT/AGENTS.md" \
  || fail "the contributor guide does not require adversarial integration review"
grep -Fq 'Specialist code review' "$ROOT/AGENTS.md" \
  || fail "the contributor guide does not require specialist code review"
grep -Fq 'Provider-native subagents are optional' "$ROOT/CLAUDE.md" \
  || fail "CLAUDE.md incorrectly depends on provider-native subagents"
grep -Fq 'carlos-algms/agentic.nvim' "$ROOT/AGENTS.md" \
  || fail "the contributor guide omits Agentic.nvim provenance"
grep -Fq 'Carlos Gomes' "$ROOT/THIRD_PARTY_NOTICES.md" \
  || fail "Agentic.nvim attribution is missing"
grep -Fq 'Those planned features are not yet' "$ROOT/README.md" \
  || fail "README does not distinguish the harness roadmap from current behavior"
grep -Fq 'docs/architecture/orchestration-harness.md' "$ROOT/README.md" \
  || fail "README does not link the canonical harness architecture"
grep -Fq 'ordinary Agent Client Protocol (ACP) sessions' "$HARNESS_SPEC" \
  || fail "harness architecture is not provider-neutral"
grep -Fq 'the harness refuses to dispatch workers' "$HARNESS_SPEC" \
  || fail "harness architecture does not require enforced worker isolation"
grep -Fq '81628c1dc07edadd1c2c3c27d8dbcb424da1dea0' "$UPSTREAM_SPEC" \
  || fail "upstream strategy does not record the current Agentic.nvim base"
grep -Fq 'agentic.nvim|https://github.com/carlos-algms/agentic.nvim.git|81628c1dc07edadd1c2c3c27d8dbcb424da1dea0|patches/agentic-hud.patch' \
  "$ROOT/nvim/plugins.lock" \
  || fail "Agentic.nvim lock entry drifted from the documented transition base"

awk -F '|' '
  /^#/ || NF == 0 { next }
  NF != 6 { exit 1 }
  $1 !~ /^[A-Za-z0-9._-]+$/ || seen[$1]++ { exit 1 }
  ($4 == "") != ($5 == "") || ($4 == "") != ($6 == "") { exit 1 }
  $4 != "" && ($5 !~ /^[0-9a-f]{64}$/ || $6 !~ /^[0-9a-f]{64}$/) { exit 1 }
' "$ROOT/nvim/plugins.lock" \
  || fail "plugin lock entries are not unique, six-column, and internally complete"
[[ "$(tail -c 1 "$ROOT/nvim/plugins.lock" | wc -l)" -eq 1 ]] \
  || fail "plugin lock must end with a newline"

sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

while IFS='|' read -r name _ _ patch patch_file_sha256 _; do
  [[ -z "$name" || "$name" == \#* || -z "$patch" ]] && continue
  [[ "$patch" == patches/*.patch && "$patch" != *..* && -f "$ROOT/$patch" ]] \
    || fail "$name has an unsafe or missing patch path"
  [[ "$(sha256_file "$ROOT/$patch")" == "$patch_file_sha256" ]] \
    || fail "$name patch checksum drifted from plugins.lock"
done < "$ROOT/nvim/plugins.lock"

if grep -Fq 'AGENTIC_PATCH_' "$ROOT/scripts/install.sh"; then
  fail "installer still hard-codes Agentic.nvim-only patch metadata"
fi
grep -Fq 'remote get-url origin' "$ROOT/scripts/install.sh" \
  || fail "installer does not verify installed plugin origins"

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
