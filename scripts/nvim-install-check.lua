-- Neovim prints +lua/startup errors but may still exit zero with +qa. Keep an
-- explicit failure exit and a success marker checked by the shell installer.
local ok, err = xpcall(function()
  assert(vim.v.errmsg == "", "Neovim startup failed: " .. vim.v.errmsg)
  assert(vim.fn.has("nvim-0.12") == 1, "Neovim 0.12 or newer is required")
  assert(vim.env.NVIM_APPNAME == "agentic-vim", "nvim launcher did not enable the isolated Agentic Vim app")
  for _, name in ipairs({ "agentic", "neo-tree", "snacks", "render-markdown", "codex_usage", "routine_jobs", "lsp", "statusbar" }) do
    require(name)
  end
  assert(
    require("agentic.ui.session_hud").previews_native_chat == true,
    "Installed Agent HUD does not preview the highlighted native chat buffer"
  )
  local config = require("agentic.config")
  local provider = config.acp_providers[config.provider].command
  assert(vim.fn.executable(provider) == 1, "Configured ACP provider is not executable: " .. provider)
  local pyright = vim.fn.stdpath("data") .. "/bin/pyright-langserver"
  assert(vim.fn.executable(pyright) == 1, "Pyright language server is not executable: " .. pyright)

  local parsers = vim.split(vim.env.AGENTIC_VIM_PARSERS or "", " ", { trimempty = true })
  if #parsers > 0 then
    -- The pinned nvim-treesitter returns false for individual failed installs;
    -- a completed async task alone does not mean compilation succeeded.
    assert(require("nvim-treesitter").install(parsers):wait(300000), "Tree-sitter parser installation failed")
    for _, language in ipairs(parsers) do
      local loaded, load_error = vim.treesitter.language.add(language)
      assert(loaded, "Cannot load Tree-sitter parser " .. language .. ": " .. tostring(load_error))
      assert(vim.treesitter.query.get(language, "highlights"), "Missing highlight query for " .. language)
      local parser = vim.treesitter.get_string_parser("", language)
      assert(parser:parse()[1], "Tree-sitter parser could not parse: " .. language)
    end
  end
  assert(vim.fn.writefile({ "verified" }, vim.env.AGENTIC_VIM_CHECK_MARKER) == 0, "Cannot write verification marker")
end, debug.traceback)
if not ok then
  vim.api.nvim_err_writeln("Agentic Vim verification failed: " .. tostring(err))
  vim.cmd("cquit 1")
end
