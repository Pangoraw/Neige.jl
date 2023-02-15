# Neige

> **Warning**
> Neige is still highly experimental, use at your own risks!

Neige is a simple evaluator of Python/Julia code using tree-sitter to match expressions under the cursor and send them to a connected session. The experience is highly inspired by the awesome [julia-vscode extension](https://www.julia-vscode.org/).

[Screencast from 15-02-2023 14:18:16.webm](https://user-images.githubusercontent.com/9824244/219038564-4e493cc3-9fd5-4450-a098-ceec4fb41135.webm)


## Usage

Install Neige as any neovim lua package using your favorite package manager and make sure to call `require("neige").instantiate({})` at least once (required only for Julia).

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

### Setup

One can change the settings for Neige using a call to `neige.setup(config)`.
The default settings are the following:

```lua
require("neige").setup({
    python_exe = "python",
    julia_exe = "julia",
    julia_opts = {
        threads = "auto",
        quiet = true,
    },
    julia_load_revise = false,
    icons = {
        failure = "✗",
        success = "✓",
        loading = "🗘",
    },
    split = "vnew",
})
```

### Running

After having installed Neige, a new Python/Julia REPL can be started using the `neige.start(opts)` function which will split the newly created REPL in a new pane.

```lua
local neige = require("neige")
neige.start({})
```

When the REPL is created, expressions can be send to the REPL using the `neige.send_command(opts)` function. It is recommended to map this function call to the <kbd>Shift</kbd> + <kbd>Enter</kbd> bindings to mimic the vscode extension.

```lua
vim.api.keymap.set('n', '<s-cr>', function()
    neige.send_command({})
end, { noremap = true })
```

## Dependencies

To have fun with Neige, you will need the following:
 - `neovim >= 0.8` (might work with earlier versions but not tested).
 - [`nvim-treesitter`](https://github.com/nvim-treesitter/nvim-treesitter/).

For using in Python scripts:

 - The [`python` grammar](github.com/tree-sitter/tree-sitter-python) for tree-sitter installed (use `:TSInstall python`).
 - `python` (or `ipython`) installed.
 - the `pynvim` package installed to the provided python installation.

For using in Julia scripts:
 - The [`julia` grammar](github.com/tree-sitter/tree-sitter-julia) for tree-sitter installed (use `:TSInstall julia`).
 - `julia >= 1.7` installed (again not tested with a lower version).

## TODOs

 - [x] Make eval request asynchronous (it currently blocks the editor, not ideal for Julia's compile times)
 - [ ] Highlight stack trace lines
 - [ ] Function to send visual selection
 - [ ] Improve node handling (when there are no node under the cursor)
 - [ ] Improve virtual text cleanup when lines are edited

## Aknowledgments

 - [lab.nvim](https://github.com/0x100101/lab.nvim/) - The virtual text implementation of Neige is currently copy-pasted from lab.
