local M = {}

local function completion_keymaps(bufnr)
  local map = function(lhs, rhs, desc, opts)
    opts = vim.tbl_extend("force", { buffer = bufnr, desc = desc }, opts or {})
    vim.keymap.set("i", lhs, rhs, opts)
  end

  map("<C-Space>", vim.lsp.completion.get, "Python: show completions")
  map("<C-j>", function()
    return vim.fn.pumvisible() == 1 and "<C-n>" or "<C-j>"
  end, "Python: next completion", { expr = true })
  map("<C-k>", function()
    return vim.fn.pumvisible() == 1 and "<C-p>" or "<C-k>"
  end, "Python: previous completion", { expr = true })
  map("<Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-n>" or "<Tab>"
  end, "Python: next completion", { expr = true })
  map("<S-Tab>", function()
    return vim.fn.pumvisible() == 1 and "<C-p>" or "<S-Tab>"
  end, "Python: previous completion", { expr = true })
  map("<CR>", function()
    return vim.fn.pumvisible() == 1 and "<C-y>" or "<CR>"
  end, "Python: accept completion", { expr = true })
end

local function navigation_keymaps(bufnr)
  local opts = { buffer = bufnr }
  local map = function(lhs, rhs, desc)
    vim.keymap.set("n", lhs, rhs, vim.tbl_extend("force", opts, { desc = desc }))
  end

  map("gd", vim.lsp.buf.definition, "Python: go to definition")
  map("gD", vim.lsp.buf.declaration, "Python: go to declaration")
  map("K", vim.lsp.buf.hover, "Python: show documentation")
  map("grr", vim.lsp.buf.references, "Python: list references")
  map("gri", vim.lsp.buf.implementation, "Python: list implementations")
  map("grt", vim.lsp.buf.type_definition, "Python: go to type definition")
  map("gO", vim.lsp.buf.document_symbol, "Python: list file symbols")
  map("gW", function()
    vim.lsp.buf.workspace_symbol(vim.fn.input("Workspace symbol: "))
  end, "Python: find workspace symbol")
  map("<leader>rn", vim.lsp.buf.rename, "Python: rename symbol")
  map("<leader>ca", vim.lsp.buf.code_action, "Python: code action")
  map("<leader>ci", vim.lsp.buf.incoming_calls, "Python: incoming calls")
  map("<leader>co", vim.lsp.buf.outgoing_calls, "Python: outgoing calls")
end

function M.setup(config)
  config = config or {}
  config.command = config.command or (vim.fn.stdpath("data") .. "/bin/pyright-langserver")

  vim.opt.completeopt = { "menu", "menuone", "noselect", "popup" }

  local group = vim.api.nvim_create_augroup("AgenticVimPythonLsp", { clear = true })
  vim.api.nvim_create_autocmd("LspAttach", {
    group = group,
    callback = function(args)
      local client = assert(vim.lsp.get_client_by_id(args.data.client_id))
      if client.name ~= "pyright" then
        return
      end

      navigation_keymaps(args.buf)
      if client:supports_method("textDocument/completion") then
        -- Pyright normally auto-triggers only after punctuation such as a dot.
        -- Include identifier characters so suggestions also appear while a
        -- name is being typed.
        local provider = client.server_capabilities.completionProvider
        local characters = provider.triggerCharacters or {}
        local seen = {}
        for _, character in ipairs(characters) do
          seen[character] = true
        end
        for character in ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_"):gmatch(".") do
          if not seen[character] then
            characters[#characters + 1] = character
          end
        end
        provider.triggerCharacters = characters

        vim.lsp.completion.enable(true, client.id, args.buf, { autotrigger = true })
        completion_keymaps(args.buf)
      end
    end,
  })

  local root_markers = {
    "pyproject.toml",
    "uv.lock",
    "requirements.txt",
    "Pipfile",
    "setup.py",
    "setup.cfg",
    ".git",
  }
  vim.lsp.config("pyright", {
    cmd = { config.command, "--stdio" },
    filetypes = { "python" },
    root_dir = function(bufnr, on_dir)
      local filename = vim.api.nvim_buf_get_name(bufnr)
      local root = vim.fs.root(filename, root_markers)
      local cwd = vim.uv.cwd()
      local cwd_prefix = cwd and (cwd .. "/") or ""
      local inside_cwd = cwd and (filename == cwd or filename:sub(1, #cwd_prefix) == cwd_prefix)
      on_dir(root or (inside_cwd and cwd) or vim.fs.dirname(filename))
    end,
    settings = {
      python = {
        analysis = {
          autoImportCompletions = true,
          autoSearchPaths = true,
          diagnosticMode = "workspace",
          indexing = true,
          typeCheckingMode = "basic",
          useLibraryCodeForTypes = true,
        },
      },
    },
  })
  vim.lsp.enable("pyright")
end

return M
