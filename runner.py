import sys, threading

from pynvim import attach


def main():
    nvim = attach("socket", path=sys.argv[1])

    code = """
    local args = ...
    local chan_id = args[1]
    require("neige"):_set_chan_id(chan_id)
    """

    channel_id = nvim.channel_id
    nvim.exec_lua(code, [channel_id,])

    thread = None

    def request_cb(*args):
        print("Got request", args, thread.ident if thread is not None else None)

    def notification_cb(type: str, args):
        if type != "eval_fetch":
            raise NotImplemented(type)

        serial, codelines = args[0]
        code = "\n".join(codelines)

        success = True
        try:
            co = compile(code, filename="REPL", mode="eval")
            res = eval(co, globals())
        except SyntaxError:
            try:
                co = compile(code, filename="REPL", mode="exec")
                res = exec(co, globals())
            except Exception as e:
                success = False
                res = e
        except Exception as e:
            success = False
            res = e

        if res is None:
            repr = ""
        else:
            repr = str(res)

        reply_code = """
        local args = ...
        local run_id = args[1]
        local res = args[2]
        require("neige").on_response(run_id, res)
        """
        nvim.exec_lua(reply_code, [serial, [success, repr]])

    def run_loop():
        nvim.run_loop(request_cb, notification_cb, setup_cb=None, err_cb=None)

    thread = threading.Thread(target=run_loop,)
    thread.daemon = True
    thread.start()


if __name__ == "__main__":
    main()
