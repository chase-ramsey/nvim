return {
	"akinsho/toggleterm.nvim",
	config = function()
		local toggleterm = require("toggleterm")
		toggleterm.setup()
		vim.keymap.set(
			"n",
			"<leader>tth",
			":ToggleTerm direction=horizontal dir=git_dir<CR>",
			{ desc = "Toggle horizontal terminal" }
		)
		vim.keymap.set(
			"n",
			"<leader>ttf",
			":ToggleTerm direction=float dir=git_dir<CR>",
			{ desc = "Toggle floating terminal" }
		)
	end,
}