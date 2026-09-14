#!/usr/bin/env bash
# Exercises Python and Rust completion through the public LSP setup entrypoint.
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
NVIM=${NVIM:-nvim}

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

command -v "$NVIM" >/dev/null 2>&1 \
  || fail "Neovim is required on PATH (set NVIM to override the command)"
nvim_version=$(
  "$NVIM" --headless -u NONE -i NONE \
    '+lua local v=vim.version(); if v.major == 0 and v.minor < 12 then vim.cmd("cquit 42") end' \
    +qa 2>&1
) || fail "Neovim 0.12 or newer is required (${nvim_version:-version check failed})"

PYRIGHT_COMMAND=${PYRIGHT_LANGSERVER:-pyright-langserver}
PYRIGHT_PATH=$(command -v "$PYRIGHT_COMMAND" 2>/dev/null) \
  || fail "pyright-langserver is required on PATH (set PYRIGHT_LANGSERVER to override the command)"
[[ -x "$PYRIGHT_PATH" ]] || fail "pyright-langserver is present but is not executable"

TEST_DIR=$(mktemp -d "${TMPDIR:-/tmp}/agentic-lsp-test.XXXXXX")
trap 'rm -rf "$TEST_DIR"' EXIT
mkdir -p "$TEST_DIR/config" "$TEST_DIR/data" "$TEST_DIR/state" \
  "$TEST_DIR/cache" "$TEST_DIR/runtime" "$TEST_DIR/python/.git" "$TEST_DIR/rust/src"
chmod 700 "$TEST_DIR/runtime"

cat > "$TEST_DIR/python/pyproject.toml" <<'TOML'
[project]
name = "agentic-python-lsp-test"
version = "0.1.0"
TOML

cat > "$TEST_DIR/python/main.py" <<'PYTHON'
value = "completion target"
value
PYTHON

cat > "$TEST_DIR/rust/Cargo.toml" <<'TOML'
[package]
name = "agentic-rust-lsp-test"
version = "0.1.0"
edition = "2021"
TOML

cat > "$TEST_DIR/rust/src/main.rs" <<'RUST'
fn main() {
    let value = String::from("completion target");
    value
}
RUST

export XDG_CONFIG_HOME="$TEST_DIR/config" XDG_DATA_HOME="$TEST_DIR/data"
export XDG_STATE_HOME="$TEST_DIR/state" XDG_CACHE_HOME="$TEST_DIR/cache"
export XDG_RUNTIME_DIR="$TEST_DIR/runtime"
export NVIM_APPNAME=agentic-lsp-test NVIM_LOG_FILE="$TEST_DIR/nvim.log"
export NVIM_CODEX_USAGE_DISABLED=1
mkdir -p "$XDG_DATA_HOME/agentic-vim/bin"
ln -s "$PYRIGHT_PATH" "$XDG_DATA_HOME/agentic-vim/bin/pyright-langserver"

CHECK="$TEST_DIR/check.lua"
cat > "$CHECK" <<'LUA'
local language = assert(vim.env.AGENTIC_LSP_LANGUAGE)
local label = language:upper() .. "_LSP"

local function finish(ok, message)
  local prefix = ok and "_PASS: " or "_FAIL: "
  vim.fn.writefile({ label .. prefix .. message }, vim.env.AGENTIC_LSP_RESULT)
  vim.cmd(ok and "qa!" or "cquit 1")
end

local completion_enable_calls = {}
local original_completion_enable = vim.lsp.completion.enable
vim.lsp.completion.enable = function(enable, client_id, bufnr, opts)
  table.insert(completion_enable_calls, {
    enable = enable,
    client_id = client_id,
    bufnr = bufnr,
    opts = opts,
  })
  return original_completion_enable(enable, client_id, bufnr, opts)
end

local completion_get_calls = 0
vim.lsp.completion.get = function()
  completion_get_calls = completion_get_calls + 1
end

local expected_name = language == "python" and "pyright" or "rust_analyzer"
local expected_executable = language == "python" and "pyright-langserver" or "rust-analyzer"

local setup_ok = pcall(function()
  vim.cmd("filetype on")
  require("lsp").setup()
  vim.cmd.edit(vim.fn.fnameescape(vim.env.AGENTIC_LSP_FILE))
end)
if not setup_ok then
  finish(false, "public require('lsp').setup() call failed")
  return
end

local bufnr = vim.api.nvim_get_current_buf()
if vim.bo[bufnr].filetype ~= language then
  finish(false, "fixture did not open with the expected filetype")
  return
end

local attached = vim.wait(20000, function()
  return #vim.lsp.get_clients({ bufnr = bufnr, name = expected_name }) > 0
end, 50)
if not attached then
  local enabled = vim.lsp.is_enabled(expected_name)
  local configured = vim.lsp.config[expected_name]
  local configured_command = configured and configured.cmd and configured.cmd[1] or "unset"
  finish(false, expected_name .. " did not automatically attach to the project buffer (enabled="
    .. tostring(enabled) .. ", command=" .. tostring(configured_command) .. ")")
  return
end

local client = vim.lsp.get_clients({ bufnr = bufnr, name = expected_name })[1]
local command = client.config.cmd
if type(command) ~= "table" or type(command[1]) ~= "string"
    or vim.fs.basename(command[1]) ~= expected_executable then
  finish(false, expected_name .. " is not using the expected language-server executable")
  return
end
if not client:supports_method("textDocument/completion", bufnr) then
  finish(false, expected_name .. " does not advertise textDocument/completion")
  return
end
if not vim.wait(10000, function()
  return client.initialized == true
end, 50) then
  finish(false, expected_name .. " did not finish initialization")
  return
end

local autotrigger_enabled = false
for _, call in ipairs(completion_enable_calls) do
  if call.enable == true and call.client_id == client.id and call.bufnr == bufnr
      and type(call.opts) == "table" and call.opts.autotrigger == true then
    autotrigger_enabled = true
    break
  end
end
if not autotrigger_enabled then
  finish(false, expected_name .. " completion was not enabled with autotrigger=true")
  return
end

local encoded_control_space = vim.api.nvim_replace_termcodes("<C-Space>", true, false, true)
local mappings = {}
for _, mapping in ipairs(vim.api.nvim_buf_get_keymap(bufnr, "i")) do
  if mapping.lhs == "<C-Space>" or mapping.lhs == "<C-@>"
      or mapping.lhs == encoded_control_space or mapping.lhsraw == encoded_control_space
      or mapping.lhsrawalt == encoded_control_space then
    table.insert(mappings, mapping)
  end
end
if #mappings == 0 then
  finish(false, "buffer lacks an insert-mode <C-Space> mapping")
  return
end
local completion_mapping
if language == "rust" then
  local rust_description = false
  for _, mapping in ipairs(mappings) do
    if type(mapping.desc) == "string" and mapping.desc:lower():find("rust", 1, true) then
      rust_description = true
      if type(mapping.callback) == "function" then
        completion_mapping = mapping
      end
    end
  end
  if not rust_description then
    finish(false, "Rust <C-Space> mapping lacks a Rust-specific description")
    return
  end
else
  for _, mapping in ipairs(mappings) do
    if type(mapping.callback) == "function" then
      completion_mapping = mapping
      break
    end
  end
end
if not completion_mapping then
  finish(false, "buffer-local <C-Space> mapping does not expose an invokable callback")
  return
end
local callback_ok = pcall(completion_mapping.callback)
if not callback_ok then
  finish(false, "buffer-local <C-Space> callback raised an error")
  return
end
if completion_get_calls ~= 1 then
  finish(false, "buffer-local <C-Space> callback did not invoke vim.lsp.completion.get")
  return
end

finish(true, expected_name .. " attached with autotrigger completion and a working <C-Space> callback")
LUA

run_slice() {
  local language=$1 file=$2 result="$TEST_DIR/$1-result" status=0 report upper_language
  case "$language" in
    python) upper_language=PYTHON ;;
    rust) upper_language=RUST ;;
    *) fail "unknown LSP test language: $language" ;;
  esac
  rm -f "$result"
  AGENTIC_LSP_LANGUAGE="$language" AGENTIC_LSP_FILE="$file" \
    AGENTIC_LSP_RESULT="$result" AGENTIC_LSP_CHECK="$CHECK" \
    "$NVIM" --headless -u NONE -i NONE \
      --cmd "set runtimepath^=$ROOT/nvim" \
      '+lua dofile(vim.env.AGENTIC_LSP_CHECK)' '+qa!' \
      > "$TEST_DIR/$language-output" 2>&1 \
    || status=$?
  if [[ -f "$result" ]]; then
    report=$(<"$result")
  else
    report="${upper_language}_LSP_FAIL: Neovim exited before the behavioral check produced a result"
  fi
  printf '%s\n' "$report"
  if [[ "${AGENTIC_LSP_DEBUG:-0}" == 1 \
      && ( ! -f "$result" || "$report" != "${upper_language}_LSP_PASS:"* ) ]]; then
    sed -n '1,200p' "$NVIM_LOG_FILE" >&2
    sed -n '1,200p' "$TEST_DIR/$language-output" >&2
  fi
  [[ "$status" == 0 && "$report" == "${upper_language}_LSP_PASS:"* ]]
}

run_slice python "$TEST_DIR/python/main.py" \
  || fail "Python LSP regression slice failed"

command -v rust-analyzer >/dev/null 2>&1 \
  || fail "rust-analyzer is required on PATH"
rust-analyzer --version >/dev/null 2>&1 \
  || fail "rust-analyzer is present but cannot execute"

run_slice rust "$TEST_DIR/rust/src/main.rs" \
  || fail "Rust LSP acceptance slice failed"
