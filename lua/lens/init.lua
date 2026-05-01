-- lua/lens/init.lua
local M = {}

local VISUAL_BLOCK = "\22"
local SELECT_BLOCK = "\19"
-- Mouse selections (and any 'selectmode' mappings) can land in Select mode
-- instead of Visual. Treat each select mode as its visual counterpart.
local SELECT_TO_VISUAL = { s = "v", S = "V", [SELECT_BLOCK] = VISUAL_BLOCK }
local namespace_id = vim.api.nvim_create_namespace("lens")
local highlights = {}

local config = {
  highlight_group = "LensHighlight",
  -- Appearance overrides (only applied when highlight_group == 'LensHighlight'):
  --   bg, fg, bold, italic, underline
  setup_keymaps = true,
  add_key = "<leader>l",
  remove_key = "<leader>l",
  clear_all_key = "<leader>L",
}

-- Only auto-creates the group when using the default name.
-- If the user sets a custom highlight_group, they are responsible for defining it.
local function setup_hl()
  if config.highlight_group ~= "LensHighlight" then
    return
  end
  local visual = vim.api.nvim_get_hl(0, { name = "Visual", link = false })
  vim.api.nvim_set_hl(0, "LensHighlight", {
    bg = config.bg or visual.bg or 0x3e4451,
    fg = config.fg,
    bold = config.bold,
    italic = config.italic,
    underline = config.underline,
  })
end

function M.add_highlight_from_visual()
  local mode = vim.fn.mode()
  mode = SELECT_TO_VISUAL[mode] or mode

  if mode ~= "v" and mode ~= "V" and mode ~= VISUAL_BLOCK then
    vim.notify("Must be called from visual mode", vim.log.levels.WARN)
    return
  end

  local start_pos = vim.fn.getpos("v")
  local end_pos = vim.fn.getpos(".")
  local bufnr = vim.api.nvim_get_current_buf()

  -- Ensure start comes before end
  if start_pos[2] > end_pos[2] or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3]) then
    start_pos, end_pos = end_pos, start_pos
  end

  local start_line = start_pos[2] - 1
  local end_line = end_pos[2] - 1
  local start_col, end_col

  if mode == "V" then
    start_col = 0
    end_col = -1
  elseif mode == VISUAL_BLOCK then
    start_col = 0
    end_col = -1
  else
    start_col = start_pos[3] - 1
    end_col = end_pos[3]
  end

  -- V-line stops at the actual line text; visual block fills the buffer width.
  local fill_eol = mode ~= "V"

  local key =
    string.format("%d:%s:%d:%d:%d:%d", bufnr, mode, start_line, start_col, end_line, end_col)

  if highlights[key] then
    vim.notify("Selection already highlighted", vim.log.levels.INFO)
  else
    M.add_highlight(bufnr, start_line, start_col, end_line, end_col, key, fill_eol)
    vim.notify("Highlight added", vim.log.levels.INFO)
  end

  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "n", false)
end

function M.remove_highlight_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cur_line = cursor[1] - 1
  local cur_col = cursor[2]

  for key, hl in pairs(highlights) do
    if hl.bufnr == bufnr and cur_line >= hl.start_line and cur_line <= hl.end_line then
      local in_range

      if hl.start_line == hl.end_line then
        in_range = hl.end_col == -1 or (cur_col >= hl.start_col and cur_col < hl.end_col)
      elseif cur_line == hl.start_line then
        in_range = cur_col >= hl.start_col
      elseif cur_line == hl.end_line then
        in_range = hl.end_col == -1 or cur_col < hl.end_col
      else
        in_range = true
      end

      if in_range then
        M.remove_highlight(key)
        vim.notify("Highlight removed", vim.log.levels.INFO)
        return
      end
    end
  end

  vim.notify("No highlight found at cursor", vim.log.levels.WARN)
end

function M.add_highlight(bufnr, start_line, start_col, end_line, end_col, key, fill_eol)
  if fill_eol == nil then
    fill_eol = true
  end
  local ids = {}

  -- nvim_buf_set_extmark returns the actual extmark id (unlike nvim_buf_add_highlight,
  -- which returns the namespace id and cannot be used with nvim_buf_del_extmark).
  local function add(line, sc, ec)
    local opts = { hl_group = config.highlight_group }
    if ec == -1 then
      if fill_eol then
        -- Highlight to end of line: range [line, sc] → [line+1, 0].
        -- hl_eol fills the visual line to the window edge past the last character.
        opts.end_line = line + 1
        opts.end_col = 0
        opts.hl_eol = true
      else
        -- Stop at the actual line length so the highlight does not extend past text.
        local lines = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)
        opts.end_line = line
        opts.end_col = lines[1] and #lines[1] or 0
      end
    else
      opts.end_line = line
      opts.end_col = ec
    end
    ids[#ids + 1] = vim.api.nvim_buf_set_extmark(bufnr, namespace_id, line, sc, opts)
  end

  if start_line == end_line then
    add(start_line, start_col, end_col)
  else
    add(start_line, start_col, -1)
    for line = start_line + 1, end_line - 1 do
      add(line, 0, -1)
    end
    add(end_line, 0, end_col)
  end

  highlights[key] = {
    bufnr = bufnr,
    ids = ids,
    start_line = start_line,
    start_col = start_col,
    end_line = end_line,
    end_col = end_col,
  }
end

function M.remove_highlight(key)
  local hl = highlights[key]
  if not hl then
    return
  end
  for _, id in ipairs(hl.ids) do
    vim.api.nvim_buf_del_extmark(hl.bufnr, namespace_id, id)
  end
  highlights[key] = nil
end

function M.clear_all()
  local seen = {}
  for _, hl in pairs(highlights) do
    if not seen[hl.bufnr] and vim.api.nvim_buf_is_valid(hl.bufnr) then
      vim.api.nvim_buf_clear_namespace(hl.bufnr, namespace_id, 0, -1)
      seen[hl.bufnr] = true
    end
  end
  highlights = {}
  vim.notify("All highlights cleared", vim.log.levels.INFO)
end

local function setup_keymaps()
  if not config.setup_keymaps then
    return
  end
  vim.keymap.set(
    { "x", "s" },
    config.add_key,
    M.add_highlight_from_visual,
    { desc = "Add highlight to visual selection" }
  )
  vim.keymap.set(
    "n",
    config.remove_key,
    M.remove_highlight_at_cursor,
    { desc = "Remove highlight at cursor" }
  )
  vim.keymap.set("n", config.clear_all_key, M.clear_all, { desc = "Clear all highlights" })
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  setup_hl()
  setup_keymaps()
end

-- LazyVim keymap spec
M.keys = {
  {
    "<leader>l",
    M.add_highlight_from_visual,
    mode = { "x", "s" },
    desc = "Add highlight to visual selection",
  },
  { "<leader>l", M.remove_highlight_at_cursor, mode = "n", desc = "Remove highlight at cursor" },
  { "<leader>L", M.clear_all, desc = "Clear all highlights" },
}

setup_hl() -- create highlight group at load; keymaps wait for M.setup()

return M
