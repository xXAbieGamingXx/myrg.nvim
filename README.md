
# myrg.nvim
A small ripgrep wrapper for Neovim with quick results and is truly asynchronous, updating the quickfixes when ripgrep finds matches.

<img width="2548" height="1432" alt="demo" src="https://github.com/user-attachments/assets/56ad3cbe-ad01-494f-9beb-4d459d5ac851" />

## Requirements
 - Neovim 0.10+
 - [ripgrep](https://github.com/burntsushi/ripgrep#installation) installation

## Installation

```lua
{
    "xXAbieGaming/myrg.nvim",
    config = function()
        require("myrg").setup({
            cmd = "path/to/rg" -- config only required if rg is not globally installed
        })
    end,
    cmd = {"Rg", "Rgcwd", "Rgff"},
},
```

Example keymaps:
```lua
vim.keymap.set('n', '<leader>fg', ":Rg<cr>")
vim.keymap.set('n', '<leader>ff', ":Rgff<cr>")
vim.keymap.set('n', '<leader>ft', function()
	local root = vim.fs.root(0, {".git"})
	require("myrg").rgcwd(root)
end)
```

## Commands

A path that is empty will result in choosing cwd, and an unspecified filetype will result in all filetypes being chosen

### `Rg`
Specify pattern and path

### `Rgff`
Specify pattern, filetype and path

### `Rgcwd`
Pass in a desired cwd, and specify pattern
