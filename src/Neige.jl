module Neige

import Neovim
import Pkg
import Logging

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
    reply_value(c, serial, res)
end

function Neovim.on_notify(::Handler, c, name, args)
    @debug "Got notification" c name args
end

function Neovim.on_request(::Handler, c, serial, name, args)
    @debug "Got request" c serial name args
    if name != "eval_fetch"
        Neovim.reply_error(c, serial, "Unhandled operation $name")
    end
    code = join(only(args), "\n")
    eval_fetch(c, serial, code)
end

function start(nvim_id, socket_path)
    Neovim.nvim_connect(socket_path, Handler(nvim_id))
    @debug "Started server" nvim.channel_id
    nothing
end

end # module
