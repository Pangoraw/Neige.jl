--[[
--
--   Neige.jl is a simple code runner for Julia code
-- inside Neovim inspired by the julia-vscode extension
--
-- TODO: function to send visual selection
-- TODO: forward log messages to the file + line
--
--]]

local function initial_command(id, path, path_to_activate)
    local julia_code = [[using Neige; Neige.start(]] .. id .. [[,"]] .. path .. [["); import Pkg;]]
    if path_to_activate ~= nil then
        julia_code = julia_code .. [[
        Pkg.activate("]] .. path_to_activate .. [["; io=devnull);]]
    else
        julia_code = julia_code .. [[;Pkg.activate(; io=devnull);]]
    end
    return julia_code
end

local function get_filepath(bufnr)
    bufnr = bufnr or 0
    return vim.api.nvim_buf_get_name(bufnr)
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
    else
        table.remove(parts, #parts)
    end
    return table.concat(parts, "/")
end

local function fileexists(path)
    return vim.fn.filereadable(path) ~= 0
end

-- Returns the path of the directory containing this file
local function folder_path()
    return get_parent(script_path())
end

local function julia_project_path()
    return folder_path() .. "/../../"
end

-- Returns the first folder than contains a Project.toml file by recursively
-- looking at parents above the current buffer file path.
local function julia_file_project_path(bufnr)
    local path = get_filepath(bufnr)
    local dir = get_parent(path)
    local i = 0

    while not fileexists(dir .. "/Project.toml") and dir ~= "" and dir ~= "/" and i < 10 do
        dir = get_parent(dir)
        i = i + 1
    end

    if not fileexists(dir .. "/Project.toml") then
        return nil
    end
    return dir
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

-- Check that the two nodes are either on the same line or on the exact line next
local function nodes_contiguous(node, next)
    local _, _, row_end, _ = node:end_()
    local row_start, _, _, _ = next:start()

    return (row_start - row_end <= 1)
end

-- Returns wether or not the node can have a docstring
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

local ns = vim.api.nvim_create_namespace("neige")

-- Extracts the range under the cursor that correspond to the first "toplevel" expression
local function extract_nodes(opts)
    opts = opts or {}
    local winnr = opts.winnr or 0
    local debug_hl = opts.debug_jl or false

    local node = ts_utils.get_node_at_cursor(winnr)
    local parent = node:parent()
    while not toplevel_node(node) do
        node = parent
        parent = node:parent()
    end

    local nodes = {node}

    -- Doc strings
    -- TODO: handle macro calls like Base.@kwdef?
    local maybe_next = node:next_named_sibling()
    if (
        node:type() == "string_literal" and
        docstringable(maybe_next) and
        nodes_contiguous(node, maybe_next)
    ) then
        table.insert(nodes, maybe_next)
    elseif docstringable(node) then
        local previous = node:prev_named_sibling()
        if (
            previous ~= nil and
            previous:type() == "string_literal" and
            nodes_contiguous(previous, node)
        ) then
            table.insert(nodes, 1, previous)
        end
    end

    if debug_hl then
        for _, n in ipairs(nodes) do
            ts_utils.highlight_node(n, 0, ns, "Comment")
        end
    end

    return nodes
end

-- NOTE: use ts_utils.goto_node(node, true, false) instead and make it work
local function goto_node(bufnr, node, goto_end)
    if goto_end then
        local row, col, _ = node:end_()
        vim.api.nvim_win_set_cursor(bufnr, { row + 1, col })
    else
        local row, col, _ = node:start()
        vim.api.nvim_win_set_cursor(bufnr, { row + 1, col })
    end
end

-- Module def

local M = {
    julia_exe = "julia",
    julia_env = julia_file_project_path,
    julia_opts = {
        threads = "auto",
        quiet = true,
    },
    split = "vnew",
    chan = nil,
    run_id = 1,
    neige_id = 1,
}

local VirtualText = require("neige.virtual_text")

function M._build_julia_cmd(args)
    table.insert(args, 1, M.julia_exe)

    local opts = M.julia_opts
    if opts.quiet then
        table.insert(args, "-q")
    end

    if opts.threads ~= nil then
        table.insert(args, "--threads=" .. opts.threads)
    end

    return args
end

-- Starts a Julia process in a side terminal
function M.start(opts)
    if not fileexists(julia_project_path() .. "/Manifest.toml") then
        print("Neige.jl: project has not been instantiated, call neige.instantiate()")
        return
    end

    opts = opts or {}
    local servername = opts.servername or vim.v.servername
    local julia_env = opts.julia_env or M.julia_env
    local split = opts.split or M.split
    local bufnr = opts.bufnr or 0

    if type(julia_env) == "function" then
        julia_env = julia_env(bufnr)
    end

    if M.chan ~= nil then
        print("error: Julia session is already started")
        return
    end

    local cmd = M._build_julia_cmd({
        "--project=" .. julia_project_path(),
        "-e", initial_command(M.neige_id, servername, julia_env),
        "-i",
    })

    if type(split) == "string" then
        vim.cmd(split)
    else
        split()
    end

    -- TODO: this is a bit of a hack, can i specify the chan id at startup?
    --       if it is not possible, the julia side should notify with the
    --       channel id using nvim_lua_eval, this way we can block requests
    --       until the channel is actually open (due to Julia side delay).
    M.chan = vim.fn.termopen(cmd) + 1
end

-- Get a ts compatible range of the current visual selection.
-- from https://github.com/theHamsta/nvim-treesitter/blob/a5f2970d7af947c066fb65aef2220335008242b7/lua/nvim-treesitter/incremental_selection.lua#L22-L30
--
-- The range of ts nodes start with 0 and the ending range is exclusive.
local function visual_selection_range()
    local _, csrow, cscol, _ = unpack(vim.fn.getpos("'<"))
    local _, cerow, cecol, _ = unpack(vim.fn.getpos("'>"))
    if csrow < cerow or (csrow == cerow and cscol <= cecol) then
        return csrow - 1, cscol - 1, cerow - 1, cecol
    else
        return cerow - 1, cecol - 1, csrow - 1, cscol
    end
end

function M.send_visual_selection(opts)
    opts = opts or {}
    local bufnr = opts.bufnr or 0

    -- https://github.com/nvim-telescope/telescope.nvim/pull/494/files
    local row_start, col_start, row_end, col_end = visual_selection_range()
    if col_end == 2147483647 then
        col_end = -1
    end
    local code = vim.api.nvim_buf_get_text(bufnr, row_start, col_start, row_end, col_end, {})

    return M._send_code({
        bufnr = bufnr,
        line_num = row_end,
    }, code)
end

-- Extract the node under the cursor and sends it to the Julia process for evaluation
-- TODO: loading indicator like in vscode.
function M.send_command(opts)
    opts = opts or {}
    local debug_hl = opts.debug_hl or false
    local bufnr = opts.bufnr or 0

    local nodes = extract_nodes({ debug_hl = debug_hl })
    local code = get_nodes_text(bufnr, nodes)

    local node = nodes[#nodes]
    local line_num, _, _ = node:end_()

    local maybe_next = node:next_named_sibling()

    local after_fn = function()
        if maybe_next ~= nil then
            goto_node(bufnr, maybe_next, false)
        else
            goto_node(bufnr, node, true)
        end
    end

    return M._send_code({
        bufnr = bufnr,
        line_num = line_num,
        after_fn = after_fn,
    }, code)
end

function M._send_code(opts, code)
    opts = opts or {}
    local bufnr = opts.bufnr or 0

    if M.chan == nil then
        print("error: Julia session is not yet created, call start()")
        return
    end

    local res = vim.rpcrequest(M.chan, "eval_fetch", code)
    if #res ~= 2 then
        print("error: wrong return value")
        return
    end

    local success = res[1]
    local repr = res[2]

    local buf_marks = VirtualText.lines[tostring(bufnr)]
    if buf_marks ~= nil then
        local previous_mark = buf_marks[tostring(opts.line_num)]
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
        line_num = opts.line_num,
        run_id = M.run_id,
        append = false,
        hl = hl,
        text = repr,
        icon = icon,
    })

    M.run_id = M.run_id + 1
    if opts.after_fn ~= nil then
        opts.after_fn()
    end
end

-- Configure parameters
function M.setup(opts)
    M = vim.tbl_deep_extend("force", M, opts)
end

-- Installs the Julia dependencies, call it once at install
function M.instantiate(opts)
    opts = opts or {}
    local split = opts.split or true

    local julia_code = [[
      import Pkg;
      @info "Installing packages..."

      Pkg.add(; url="https://github.com/bfredl/Neovim.jl", rev="0824be8605505c51dea1942a8268bed83f972412");
      Pkg.instantiate();
      Pkg.status();

      import Neige
      @info "Setup done, have fun!"
    ]]

    local cmd = M._build_julia_cmd({
        "--project=" .. julia_project_path(),
        "-e", julia_code,
    })

    if split then
        vim.cmd("vnew")
        vim.fn.termopen(cmd)
    else
        vim.fn.jobstart(cmd)
    end
end

return M
