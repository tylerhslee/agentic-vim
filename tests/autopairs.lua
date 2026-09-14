local function type_insert(keys)
  local encoded = vim.api.nvim_replace_termcodes("i" .. keys .. "<Esc>", true, false, true)
  vim.api.nvim_feedkeys(encoded, "xt", false)
end

local bufnr = vim.api.nvim_create_buf(false, true)
vim.api.nvim_set_current_buf(bufnr)
vim.bo[bufnr].filetype = "lua"

for opener, expected in pairs({
  ["("] = "()",
  ["["] = "[]",
  ["{"] = "{}",
  ['"'] = '""',
  ["'"] = "''",
}) do
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  type_insert(opener)
  assert(vim.api.nvim_get_current_line() == expected, "Missing automatic pair for " .. opener)
end

vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { ")" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
type_insert(")")
assert(vim.api.nvim_get_current_line() == ")", "Existing closer was duplicated")

vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, { "" })
vim.api.nvim_win_set_cursor(0, { 1, 0 })
type_insert("(<BS>")
assert(vim.api.nvim_get_current_line() == "", "Backspace did not remove an empty pair together")

vim.api.nvim_buf_delete(bufnr, { force = true })
