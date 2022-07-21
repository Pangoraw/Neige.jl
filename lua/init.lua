--[[
--
--  Nulia.jl is a simple code runner for Julia code
-- inside Neovim inspired by the julia-vscode extension
--
--]]

local VirtualText = require("Nulia.virtual_text")
local M = { chan = nil, run_id = 1 }

local function initial_command(path)
    return [[using Nulia; Nulia.start("]] .. path .. [[")]]
end

-- http://stackoverflow.com/questions/6380820/ddg#23535333
local function script_path()
   local str = debug.getinfo(2, "S").source:sub(2)
   return str:match("(.*/)")
end

-- Splits the path and return the parent path
-- @param path - string
-- @returns parent - str parent path
local function get_parent(path)
    local parts = vim.split(path, "/", { plain = true })
    if string.len(parts[#parts]) > 0 then
        parts[#parts] = ""
    end
    return table.concat(parts, "/")
end

-- Returns the path of the directory containing this file
local function folder_path()
    return get_parent(script_path())
end

local function julia_project_path()
    return folder_path()
end

function M.start()
    if M.chan ~= nil then
        P("error: term is already started")
        return
    end

    local cmd = {
        "julia",
        "-q",
        [[--project=]] .. julia_project_path(),
        "-e", initial_command(vim.v.servername),
        "-i",
    }
    vim.cmd("vnew")

    -- TODO: this is a bit of a hack, can i specify the chan id at startup?
    --       if it is not possible, the julia side should notify with the
    --       channel id using nvim_lua_eval.
    M.chan = vim.fn.termopen(cmd) + 1
end

local ts_utils = require("nvim-treesitter.ts_utils")
local function toplevel_node(node)
    local parent = node:parent()
    return parent == nil or parent:type() == "source_file"
end

local function get_nodes_text(bufnr, nodes)
    local row_start, col_start, row_end, col_end = math.huge, math.huge, 0, 0

    for _, node in ipairs(nodes) do
        local new_row_start, new_col_start, new_row_end, new_col_end = node:range()
        row_start = math.min(new_row_start, row_start)
        col_start = math.min(new_col_start, col_start)

        row_end = math.max(new_row_end, row_end)
        col_end = math.max(new_col_end, col_end)
    end

    return vim.api.nvim_buf_get_text(bufnr, row_start, col_start, row_end, col_end, {})
end

-- TODO: support f(x) = x syntax
local function docstringable(node)
  if node == nil then
      return false
  end
  local type = node:type()
  return (
      type == "function_definition" or
      type == "struct_definition" or
      type == "module_definition"
  )
end

local ns = vim.api.nvim_create_namespace("nulia")

-- Extracts the range under the cursor that correspond to the first "toplevel" expression
local function extract_nodes(opts)
    opts = opts or {}
    local winnr = opts.winnr or 0
    local debug_hl = opts.debug_jl or false

    local node = ts_utils.get_node_at_cursor(winnr)
    local parent = node:parent()
    while (
      parent ~= nil and parent:type() ~= "source_file" -- and
      -- (not toplevel_node(node) or
      --  parent:start() == node:start())
      ) do
        node = parent
        parent = node:parent()
    end

    local nodes = {node}

    -- Doc strings
    local maybe_next = node:next_named_sibling()
    if node:type() == "string_literal" and docstringable(maybe_next) then
        table.insert(nodes, maybe_next)
    end

    if debug_hl then
        for _, n in ipairs(nodes) do
            ts_utils.highlight_node(n, 0, ns, "Comment")
        end
    end

    return nodes
end

-- NOTE: use ts_utils.goto_node(node, true, false) instead and make it work
local function goto_node(node, goto_end)
    if goto_end then
        local row, col, _ = node:end_()
        vim.api.nvim_win_set_cursor(0, { row + 1, col })
    else
        local row, col, _ = node:start()
        vim.api.nvim_win_set_cursor(0, { row + 1, col - 1 })
    end
end

function M.send_command(opts)
    opts = opts or {}
    local debug_hl = opts.debug_hl or false

    if M.chan == nil then
        P("Something went wrong")
        return
    end
    local bufnr = 0
    local nodes = extract_nodes({ debug_hl = debug_hl })
    local code = get_nodes_text(0, nodes)
    local res = vim.rpcrequest(M.chan, "eval_fetch", code)

    if #res ~= 2 then
        print("error: wrong return value")
        return
    end

    local node = nodes[#nodes]

    local success = res[1]
    local repr = res[2]
    local line_num, _, _ = node:end_()

    local buf_marks = VirtualText.lines[tostring(bufnr)]
    if buf_marks ~= nil then
        local previous_mark = buf_marks[tostring(line_num)]
        if previous_mark ~= nil then
            VirtualText:clear(bufnr, previous_mark.markId)
        end
    end

    local hl = "DiagnosticInfo"
    local icon = "✓"
    if not success then
        hl = "DiagnosticError"
        icon = "✗"
    end

    VirtualText:render({
        buf_handle = bufnr,
        line_num = line_num,
        run_id = M.run_id,
        append = false,
        hl = hl,
        text = repr,
        icon = icon,
    })

    M.run_id = M.run_id + 1
    local maybe_next = node:next_sibling()
    if maybe_next ~= nil then
        goto_node(maybe_next, true)
    else
        goto_node(node, false)
    end
end

-- TODO: setup options
function M.setup() end

function M.instantiate(popup)
    local julia_code = [[
      import Pkg;
      Pkg.instantiate();
      import Nulia
      @info "Setup done!"
    ]]

    local cmd = {
        "julia",
        "-q",
        [[--project=]] .. julia_project_path(),
        "-e",
        julia_code,
    }

    if popup then
      vim.fn.termopen(cmd)
    else
      vim.fn.jobstart(cmd)
    end
end

local map = vim.keymap.set
map('n', '<leader>js', function()
    nulia = M
    nulia.start()
end)
map('n', '<s-cr>', function()
    nulia.send_command()
end)

return M
