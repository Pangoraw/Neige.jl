module Nulia

import Neovim
import Pkg
import Logging

struct Handler end

function repr_value(other)
    repr(other)
end
function repr_value(::Nothing)
    ""
end

function reply_value(c, serial, val)
    Neovim.reply_result(c, serial, [true, repr_value(val)])
end
function reply_error(c, serial, ex)
    Neovim.reply_result(c, serial, [false, repr_value(ex)])
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

function start(socket_path)
    nvim = Neovim.nvim_connect(socket_path, Handler())

    @debug "Started server" nvim.channel_id

    # Neovim.send_request(nvim, "nvim_exec_lua", "nulia.ready = true")
    Pkg.activate("@1.7")
    nothing
end

end # module
