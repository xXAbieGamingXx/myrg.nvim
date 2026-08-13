
# myrg.nvim
A small ripgrep wrapper for Neovim with quick results and is truly asynchronous, updating the quickfixes when ripgrep finds matches.

<img width="2560" height="1440" alt="demo" src="https://github.com/user-attachments/assets/bed3c00a-4149-4688-8723-da2c8a2c22e6" />

## Requirements
 - Neovim 0.10+
 - [ripgrep](https://github.com/burntsushi/ripgrep#installation) installation

## Installation

```lua
{
    "xXAbieGamingXx/myrg.nvim",
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

I would highly recommend disabling Treesitter for the quickfix filetype, it changes nothing about the visuals and adds almost all of the ui lag.
```lua
vim.api.nvim_create_autocmd("FileType", {
	pattern = "qf",
	callback = function(args)
		pcall(vim.treesitter.stop, args.buf)
	end,
})
```

## Commands

All commands will open up a quickfix window with the results.

A path that is empty will result in choosing cwd, and an unspecified filetype will result in all filetypes being chosen.

### `Rg`
Specify pattern and path

### `Rgff`
Specify pattern, filetype and path

### `Rgcwd`
Pass in a desired cwd, and specify pattern
