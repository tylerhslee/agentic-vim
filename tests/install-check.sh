#!/usr/bin/env bash
# Exercises the same Neovim verification entrypoint used by install.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
NVIM=${NVIM:-nvim}
TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/agentic-vim-check-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
export XDG_CONFIG_HOME="$TEST_DIR/config" XDG_DATA_HOME="$TEST_DIR/data"
export XDG_STATE_HOME="$TEST_DIR/state" XDG_CACHE_HOME="$TEST_DIR/cache"
export NVIM_LOG_FILE="$TEST_DIR/nvim.log" NVIM_CODEX_USAGE_DISABLED=1
export AGENTIC_VIM_CHECK_SCRIPT="$ROOT/scripts/nvim-install-check.lua"
export AGENTIC_VIM_CHECK_MARKER="$TEST_DIR/success"
cat > "$TEST_DIR/init.lua" <<'LUA'
for _, name in ipairs({ 'agentic', 'neo-tree', 'snacks', 'render-markdown', 'codex_usage', 'routine_jobs' }) do
  package.preload[name] = function() return {} end
end
package.preload['agentic.config'] = function()
  return { provider = 'test', acp_providers = { test = { command = vim.v.progpath } } }
end
package.preload['nvim-treesitter'] = function()
  return { install = function()
    return { wait = function()
      if vim.env.TEST_CASE == 'install-error' then error('test timeout') end
      return vim.env.TEST_CASE ~= 'install-false'
    end }
  end }
end
if vim.env.TEST_CASE == 'plugin-missing' then
  package.preload['agentic'] = function() error('test missing plugin') end
end
if vim.env.TEST_CASE == 'provider-missing' then
  package.preload['agentic.config'] = function()
    return { provider = 'test', acp_providers = { test = { command = '/nonexistent/agentic-provider' } } }
  end
end
if vim.env.TEST_CASE == 'startup-error' then error('test startup error') end
if vim.env.TEST_CASE == 'query-missing' then vim.treesitter.query.get = function() return nil end end
LUA
run_case() {
  local name=$1 parsers=$2 expected=$3 status=0
  rm -f "$AGENTIC_VIM_CHECK_MARKER"
  TEST_CASE="$name" AGENTIC_VIM_PARSERS="$parsers" \
    "$NVIM" --headless -u "$TEST_DIR/init.lua" -i NONE \
    '+lua dofile(vim.env.AGENTIC_VIM_CHECK_SCRIPT)' +qa > "$TEST_DIR/output" 2>&1 || status=$?
  if [[ "$expected" == success ]]; then
    if [[ "$status" != 0 || ! -f "$AGENTIC_VIM_CHECK_MARKER" ]]; then
      cat "$TEST_DIR/output"; printf 'FAIL: %s\n' "$name"; exit 1
    fi
  elif [[ "$status" == 0 || -e "$AGENTIC_VIM_CHECK_MARKER" ]]; then
    cat "$TEST_DIR/output"; printf 'FAIL: %s incorrectly succeeded\n' "$name"; exit 1
  fi
  printf 'PASS: %s\n' "$name"
}
run_case startup-error '' failure
run_case plugin-missing '' failure
run_case provider-missing '' failure
run_case install-false lua failure
run_case install-error lua failure
run_case parser-missing nonexistent_agentic_parser failure
run_case query-missing lua failure
run_case healthy lua success
run_case skip-parsers '' success
