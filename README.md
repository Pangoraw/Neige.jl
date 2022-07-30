# Neige.jl

> **Warning**
> Neige.jl is still highly experimental, use at your own risks!

Neige is a simple evaluator of Julia code using tree-sitter to match expressions under the cursor and send them to a connected session. The experience is highly inspired by the awesome [julia-vscode extension](https://www.julia-vscode.org/).

![neige_demo](https://user-images.githubusercontent.com/9824244/181382882-a00b45a0-0814-496b-a5ef-2b877427fb8a.gif)


## Usage

Install Neige as any neovim lua package using your favorite package manager and make sure to call `require("neige").instantiate({})` at least once.

Using [paq-nvim](https://github.com/savq/paq-nvim)

```lua
require "paq" {
    -- ...
    {'Pangoraw/Neige.jl', run = function()
        require("neige").instantiate({ popup = true })
    end};
    -- ...
}
```

After having installed Neige, a new Julia REPL can be started using the `neige.start(opts)` function which will split the newly created REPL in a new pane.

```lua
local neige = require("neige")
neige.start({})
```

When the REPL is created, Julia expressions can be send to the REPL using the `neige.send_command(opts)` function. It is recommended to map this function call to the <kbd>Shift</kbd> + <kbd>Enter</kbd> bindings to mimic the vscode extension.

```lua
vim.api.keymap.set('n', '<s-cr>', function()
    neige.send_command({})
end, { noremap = true })
```

## Dependencies

To have fun with Neige, you will need the following:
 - `neovim >= 0.8` (might work with earlier versions but not tested).
 - [`nvim-treesitter`](https://github.com/nvim-treesitter/nvim-treesitter/).
 - The [`julia` grammar](github.com/tree-sitter/tree-sitter-julia) for tree-sitter installed (use `:TSInstall julia`).
 - `julia >= 1.7` installed (again not tested with below version).

## TODOs

 - [x] Make eval request asynchronous (it currently blocks the editor, not ideal for Julia's compile times)
 - [ ] Highlight stack trace lines
 - [ ] Function to send visual selection
 - [ ] Improve node handling (when there are no node under the cursor)
 - [ ] Improve virtual text cleanup when lines are edited

## Aknowledgments

 - [lab.nvim](https://github.com/0x100101/lab.nvim/) - The virtual text implementation of Neige is currently copy-pasted from lab.
