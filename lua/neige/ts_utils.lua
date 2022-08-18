local api = vim.api

local ts_utils = require("nvim-treesitter.ts_utils")
local parsers = require("nvim-treesitter.parsers")

local M = {}

-- based on ts_utils.get_node_at_cursor(winnr, ignore_injected_langs) but with non named nodes too.
function M.get_node_at_cursor(winnr, opts)
  winnr = winnr or 0
  local enforce_named = opts.enforce_named
  local ignore_injected_langs = opts.ignore_injected_langs or false

  local cursor = api.nvim_win_get_cursor(winnr)
  local cursor_range = { cursor[1] - 1, cursor[2] }

  local buf = vim.api.nvim_win_get_buf(winnr)
  local root_lang_tree = parsers.get_parser(buf)
  if not root_lang_tree then
    return
  end

  local root
  if ignore_injected_langs then
    for _, tree in ipairs(root_lang_tree:trees()) do
      local tree_root = tree:root()
      if tree_root and ts_utils.is_in_node_range(tree_root, cursor_range[1], cursor_range[2]) then
        root = tree_root
        break
      end
    end
  else
    root = ts_utils.get_root_for_position(cursor_range[1], cursor_range[2], root_lang_tree)
  end

  if not root then
    return
  end

  if enforce_named then
    return root:named_descendant_for_range(cursor_range[1], cursor_range[2], cursor_range[1], cursor_range[2])
  else
    return root:descendant_for_range(cursor_range[1], cursor_range[2], cursor_range[1], cursor_range[2])
  end
end

return M
