module Neige

import Neovim
import Pkg
import Logging
import REPL

struct Handler
    nvim_id::Int
    req_channel::Channel
    eval_task::Task
end

repr_value(other) = repr(other)
repr_value(::Nothing) = ""

function repr_error(ex)
    io = IOBuffer()
    showerror(io, ex)
    String(take!(io))
end

function nvim_exec_lua(c, a_code, a_args)
    res = Neovim.send_request(c, :nvim_exec_lua, Any[a_code, a_args])
    @debug "result from lua" res
end

function reply_result(c, serial, val::Vector)
    @debug "sending reply" serial val
    lua_code = """
    require("neige").on_response(...)
    """
    nvim_exec_lua(c, lua_code, (serial, val))
end

function reply_value(c, serial, val)
    reply_result(c, serial, [true, repr_value(val)])
end
function reply_error(c, serial, ex)
    reply_result(c, serial, [false, repr_error(ex)])
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

function Neovim.on_notify(handler::Handler, c, name, args)
    @debug "Got notification" c name args
    if name == "eval_fetch"
        put!(handler.req_channel, args)
    elseif name == "interrupt"
        schedule(handler.eval_task, InterruptException(); error=true)
    else
        throw("Unknown method $name")
    end
end

function Neovim.on_request(::Handler, c, serial, name, args...)
    @error "Got invalid request" name
    Neovim.reply_error(c, serial, "Client cannot handle request, please override `on_request`")
end

function start(nvim_id, socket_path)
    nvim = Ref{Any}(nothing)
    chan = Channel()
    task = Task() do
        while isopen(chan)
            try
                args = take!(chan)
                serial, codes = first(args)
                code = join(codes, "\n")
                while isnothing(nvim[])
                    sleep(.5)
                end
                Base.@invokelatest eval_fetch(nvim[], serial, code)
            catch e
                if e isa InterruptException
                    continue
                end
                @warn "Error during evaluation task" exception=(e, catch_backtrace())
                continue
            end
        end
    end
    schedule(task)
    handler = Handler(nvim_id, chan, task)
    nvim[] = Neovim.nvim_connect(socket_path, handler)

    channel_id = nvim[].channel_id
    code = """
    require("neige"):_set_chan_id(...)
    """
    nvim_exec_lua(nvim[], code, (channel_id,))

    @debug "Started server" channel_id
    nothing
end

end # module
