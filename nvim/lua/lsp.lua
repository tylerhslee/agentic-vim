-- Native LSP wiring (Neovim 0.11+ ships default server configs, e.g.
-- pyright, in its runtime, so no nvim-lspconfig plugin is needed).
local M = {}

function M.setup()
  vim.lsp.enable("pyright")

  vim.api.nvim_create_autocmd("LspAttach", {
    callback = function(args)
      local bufnr = args.buf
      local client = vim.lsp.get_client_by_id(args.data.client_id)

      vim.keymap.set("n", "gd", vim.lsp.buf.definition, { buffer = bufnr, desc = "LSP: go to definition" })
      vim.keymap.set("n", "K", vim.lsp.buf.hover, { buffer = bufnr, desc = "LSP: hover docs" })

      if client and client:supports_method("textDocument/completion") then
        vim.lsp.completion.enable(true, client.id, bufnr, { autotrigger = true })
      end
    end,
  })
end

return M
