module Neige

import Neovim
import Pkg
import Logging
import REPL

struct Handler
    nvim_id::Int
end

repr_value(other) = repr(other)
repr_value(::Nothing) = ""

function repr_error(ex)
    io = IOBuffer()
    showerror(io, ex)
    String(take!(io))
end

function nvim_exec_lua(c, a_code, a_args)
    Neovim.send_request(c, :nvim_exec_lua, Any[a_code, a_args])
end

function reply_result(c, serial, val)
    lua_code = """
    require("neige"):on_response(...)
    """
    nvim_exec_lua(c, lua_code, (serial, val))
end

function reply_value(c, serial, val)
    Neovim.reply_result(c, serial, [true, repr_value(val)])
end
function reply_error(c, serial, ex)
    Neovim.reply_result(c, serial, [false, repr_error(ex)])
end

function eval_fetch(c, serial, code)
    res = try
        expr = Meta.parse(code)
        Core.eval(Main, expr)
    catch ex
        reply_error(c, serial, ex)
        return
    end

    if REPL.ends_with_semicolon(code)
        res = nothing
    end

    reply_value(c, serial, res)
end

#=
function Neovim.on_request(::Handler, c, serial, name, args)
    @debug "Got request" c name args
    Neovim.reply_error(c, serial, "Client cannot handle request, please override `on_request`")
end
=#

function Neovim.on_request(::Handler, c, serial, name, args)
    codes = only(args)
    @debug "Got notification" c name serial args
    if name != "eval_fetch"
        Neovim.reply_error(c, serial, "Unhandled operation $name")
    end
    code = join(codes, "\n")
    eval_fetch(c, serial, code)
end

function start(nvim_id, socket_path)
    nvim = Neovim.nvim_connect(socket_path, Handler(nvim_id))
    @debug "Started server" nvim.channel_id
    nothing
end

end # module
