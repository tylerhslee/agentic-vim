local NuiTree = require("nui.tree")

-- Replacing one child level may reuse unchanged sibling nodes. Their complete
-- subtrees must survive repeated replacements without retaining dangling ids.
local tree_buf = vim.api.nvim_create_buf(false, true)
local root = NuiTree.Node({ id = "root" }, {
  NuiTree.Node({ id = "left" }, { NuiTree.Node({ id = "leaf" }) }),
  NuiTree.Node({ id = "right" }),
})
local tree = NuiTree({
  bufnr = tree_buf,
  nodes = { root },
  get_node_id = function(node) return node.id end,
})
local siblings = tree:get_nodes("root")
siblings[2] = NuiTree.Node({ id = "replacement" })
tree:set_nodes(siblings, "root")
assert(tree:get_node("leaf"), "Reusing a sibling discarded its existing subtree")
local repeated = tree:get_nodes("root")
repeated[2] = NuiTree.Node({ id = "replacement-again" })
tree:set_nodes(repeated, "root")
assert(tree:get_node("leaf"), "Repeated sibling replacement corrupted the tree")
vim.api.nvim_buf_delete(tree_buf, { force = true })

-- A watched directory can disappear after the synchronous stat filter but
-- before the asynchronous open. The refresh must still finish without an
-- error-level notification.
local directory = vim.fn.tempname()
vim.fn.mkdir(directory, "p")
vim.fn.writefile({ "seed" }, directory .. "/seed.txt")
local command = require("neo-tree.command")
local manager = require("neo-tree.sources.manager")
local log = require("neo-tree.log")
local original_opendir = vim.uv.fs_opendir
local original_error = log.error
local state
local original_scan_mode
local scan_mode_saved = false
local ok, err = xpcall(function()
  command.execute({ action = "focus", source = "filesystem", dir = directory })
  state = manager.get_state("filesystem")
  original_scan_mode = state.async_directory_scan
  scan_mode_saved = true
  assert(vim.wait(2000, function()
    return state.tree and state.tree:get_node(directory .. "/seed.txt") ~= nil
  end), "Filesystem fixture did not load")

  local errors = {}
  local injected = false
  local completed = false
  log.error = function(...)
    errors[#errors + 1] = table.concat(vim.tbl_map(tostring, { ... }), " ")
  end
  vim.uv.fs_opendir = function(path, callback, entries)
    if not injected and path == directory and type(callback) == "function" then
      injected = true
      vim.schedule(function()
        callback("ENOENT: injected disappearance", nil)
      end)
      return
    end
    return original_opendir(path, callback, entries)
  end

  manager.refresh("filesystem", function() completed = true end)
  local finished = vim.wait(2000, function() return completed end, 20)

  assert(injected, "Disappearance race was not injected")
  assert(finished, "Filesystem refresh did not complete after a directory disappeared")
  assert(#errors == 0, "Expected disappearance was logged as an error: " .. table.concat(errors, "\n"))

  injected = false
  completed = false
  state.async_directory_scan = "never"
  vim.uv.fs_opendir = function(path, callback, entries)
    if not injected and path == directory and type(callback) ~= "function" then
      injected = true
      return nil, "ENOENT: injected synchronous disappearance"
    end
    return original_opendir(path, callback, entries)
  end
  manager.refresh("filesystem", function() completed = true end)
  assert(injected, "Synchronous disappearance race was not injected")
  assert(vim.wait(2000, function() return completed end, 20),
    "Synchronous refresh did not complete after a directory disappeared")
  assert(#errors == 0, "Synchronous disappearance was logged as an error: " .. table.concat(errors, "\n"))
end, debug.traceback)
vim.uv.fs_opendir = original_opendir
log.error = original_error
if state and scan_mode_saved then
  state.async_directory_scan = original_scan_mode
end
command.execute({ action = "close", source = "filesystem" })
vim.fn.delete(directory, "rf")
assert(ok, err)
