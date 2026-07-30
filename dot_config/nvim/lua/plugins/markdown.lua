return {
  -- Better in-buffer rendering (already from the extra, but customize if you want)
  {
    "MeanderingProgrammer/render-markdown.nvim",
    opts = {
      heading = {
        sign = false, -- hide signs if you prefer cleaner look
        icons = {}, -- or customize icons
      },
      code = {
        sign = false,
        width = "block", -- makes code blocks full width
        right_pad = 1,
      },
      checkbox = {
        enabled = true,
      },
      -- Add more options from the plugin docs if needed
    },
  },

  -- Optional: Better image support in preview and rendering
  {
    "3rd/image.nvim",
    opts = {
      backend = "kitty", -- or "ueberzug" / "sixel" depending on your terminal
      integrations = {
        markdown = {
          enabled = true,
          clear_in_insert_mode = false,
          download_remote_images = true,
        },
      },
    },
  },

  -- Change preview keymap if you don't like the default
  {
    "iamcco/markdown-preview.nvim",
    keys = {
      { "<leader>mp", "<cmd>MarkdownPreviewToggle<cr>", desc = "Markdown Preview" },
    },
  },
}
