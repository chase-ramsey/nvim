return {
  "s1n7ax/nvim-window-picker",
  name = "window-picker",
  event = "VeryLazy",
  version = "2.*",
  config = function()
    local window_picker = require("window-picker")

    local function go_to_picked()
      local window_id = window_picker.pick_window({
        picker_config = {
          statusline_winbar_picker = {
            use_winbar = "always"
          }
        },
        show_prompt = false,
      })
      if window_id == nil then
        return
      end

      vim.api.nvim_set_current_win(window_id)
    end

    vim.keymap.set("n", "<leader>r", go_to_picked, { silent = true, nowait = true, desc = "Pick a window" })
  end,
}
