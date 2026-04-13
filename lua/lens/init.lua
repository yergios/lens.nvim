-- lua/lens/init.lua
local M = {}

local namespace_id = vim.api.nvim_create_namespace 'lens'
local highlights = {}
local config = {
  highlight_group = 'LensHighlight',
  bg = nil,
  fg = nil,
  bold = nil,
  italic = nil,
  underline = nil,
  setup_keymaps = true,
  add_key = '<leader>l',
  remove_key = '<leader>l',
  clear_all_key = '<leader>L',
}
local setup_called = false

-- Initialize defaults on first use
local function ensure_setup()
  if setup_called then
    return
  end
  setup_called = true

  -- Create custom highlight group
  if config.highlight_group == 'LensHighlight' then
    -- Try more vibrant highlight groups for better visibility while maintaining readability
    local visual_hl = vim.api.nvim_get_hl(0, { name = 'Visual', link = false })
    local default_bg = visual_hl.bg or 0x3e4451

    vim.api.nvim_set_hl(0, 'LensHighlight', {
      bg = config.bg or default_bg,
      fg = config.fg,
      bold = config.bold,
      italic = config.italic,
      underline = config.underline,
    })
  end

  -- Set up keymaps if enabled
  if config.setup_keymaps then
    -- Visual mode: add highlight
    vim.keymap.set('x', config.add_key, function()
      require('lens').add_highlight_from_visual()
    end, { desc = 'Add highlight to visual selection' })

    -- Normal mode: remove highlight at cursor
    vim.keymap.set('n', config.remove_key, function()
      require('lens').remove_highlight_at_cursor()
    end, { desc = 'Remove highlight at cursor' })

    -- Clear all highlights
    vim.keymap.set('n', config.clear_all_key, function()
      require('lens').clear_all()
    end, { desc = 'Clear all highlights' })
  end
end

function M.setup(opts)
  opts = opts or {}
  config = vim.tbl_deep_extend('force', config, opts)
  setup_called = false -- Allow re-setup
  ensure_setup()
end

-- Default keymaps for LazyVim integration
M.keys = {
  {
    '<leader>l',
    function()
      require('lens').add_highlight_from_visual()
    end,
    mode = 'x',
    desc = 'Add highlight to visual selection',
  },
  {
    '<leader>l',
    function()
      require('lens').remove_highlight_at_cursor()
    end,
    mode = 'n',
    desc = 'Remove highlight at cursor',
  },
  {
    '<leader>L',
    function()
      require('lens').clear_all()
    end,
    desc = 'Clear all highlights',
  },
}

-- Auto-initialize with defaults when module loads
ensure_setup()

function M.add_highlight_from_visual()
  -- Get the current visual selection while still in visual mode
  local mode = vim.fn.mode()

  if mode ~= 'v' and mode ~= 'V' and mode ~= '\22' then
    vim.notify('Must be called from visual mode', vim.log.levels.WARN)
    return
  end

  -- Get selection bounds
  local start_pos = vim.fn.getpos 'v'
  local end_pos = vim.fn.getpos '.'
  local bufnr = vim.api.nvim_get_current_buf()

  -- Ensure start comes before end
  if
    start_pos[2] > end_pos[2]
    or (start_pos[2] == end_pos[2] and start_pos[3] > end_pos[3])
  then
    start_pos, end_pos = end_pos, start_pos
  end

  local start_line = start_pos[2] - 1
  local end_line = end_pos[2] - 1
  local start_col, end_col

  -- Handle different visual modes
  if mode == 'V' then
    -- V-line mode: highlight entire lines
    start_col = 0
    end_col = -1 -- -1 means end of line
  elseif mode == '\22' then
    -- Visual block mode: use column positions
    start_col = math.min(start_pos[3] - 1, end_pos[3] - 1)
    end_col = math.max(start_pos[3], end_pos[3])
  else
    -- Character visual mode
    start_col = start_pos[3] - 1
    end_col = end_pos[3]
  end

  -- Check if this selection is already highlighted
  local selection_key = string.format(
    '%d:%s:%d:%d:%d:%s',
    bufnr,
    mode,
    start_line,
    start_col,
    end_line,
    tostring(end_col)
  )

  if highlights[selection_key] then
    vim.notify('Selection already highlighted', vim.log.levels.INFO)
  else
    -- Add new highlight
    M.add_highlight(
      bufnr,
      start_line,
      start_col,
      end_line,
      end_col,
      selection_key
    )
    vim.notify('Highlight added', vim.log.levels.INFO)
  end

  -- Return to normal mode
  vim.api.nvim_feedkeys(
    vim.api.nvim_replace_termcodes('<Esc>', true, false, true),
    'n',
    false
  )
end

function M.remove_highlight_at_cursor()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local cursor_line = cursor[1] - 1 -- Convert to 0-based
  local cursor_col = cursor[2]

  -- Find any highlight that contains the cursor position
  for selection_key, highlight in pairs(highlights) do
    if highlight.bufnr == bufnr then
      local in_range = false

      -- Check if cursor is within the highlighted range
      if
        cursor_line >= highlight.start_line
        and cursor_line <= highlight.end_line
      then
        if highlight.start_line == highlight.end_line then
          -- Single line: check column range
          if highlight.end_col == -1 then
            -- Full line highlight
            in_range = true
          else
            -- Partial line highlight
            in_range = cursor_col >= highlight.start_col
              and cursor_col < highlight.end_col
          end
        else
          -- Multi-line: cursor is within line range
          if cursor_line == highlight.start_line then
            in_range = cursor_col >= highlight.start_col
          elseif cursor_line == highlight.end_line then
            in_range = highlight.end_col == -1 or cursor_col < highlight.end_col
          else
            in_range = true -- Middle line
          end
        end
      end

      if in_range then
        M.remove_highlight(selection_key)
        vim.notify('Highlight removed', vim.log.levels.INFO)
        return
      end
    end
  end

  vim.notify('No highlight found at cursor', vim.log.levels.WARN)
end

-- Keep the old function for backward compatibility
function M.toggle_highlight()
  local mode = vim.fn.mode()
  if mode == 'v' or mode == 'V' or mode == '\22' then
    M.add_highlight_from_visual()
  else
    M.remove_highlight_at_cursor()
  end
end

function M.add_highlight(
  bufnr,
  start_line,
  start_col,
  end_line,
  end_col,
  selection_key
)
  local highlight_ids = {}

  -- Single line selection
  if start_line == end_line then
    local id = vim.api.nvim_buf_add_highlight(
      bufnr,
      namespace_id,
      config.highlight_group,
      start_line,
      start_col,
      end_col
    )
    table.insert(highlight_ids, id)
  else
    -- Multi-line selection
    -- First line
    local id = vim.api.nvim_buf_add_highlight(
      bufnr,
      namespace_id,
      config.highlight_group,
      start_line,
      start_col,
      -1
    )
    table.insert(highlight_ids, id)

    -- Middle lines
    for line = start_line + 1, end_line - 1 do
      id = vim.api.nvim_buf_add_highlight(
        bufnr,
        namespace_id,
        config.highlight_group,
        line,
        0,
        -1
      )
      table.insert(highlight_ids, id)
    end

    -- Last line
    if end_line > start_line then
      id = vim.api.nvim_buf_add_highlight(
        bufnr,
        namespace_id,
        config.highlight_group,
        end_line,
        0,
        end_col
      )
      table.insert(highlight_ids, id)
    end
  end

  highlights[selection_key] = {
    bufnr = bufnr,
    ids = highlight_ids,
    start_line = start_line,
    start_col = start_col,
    end_line = end_line,
    end_col = end_col,
  }
end

function M.remove_highlight(selection_key)
  local highlight = highlights[selection_key]
  if highlight then
    -- Clear the namespace for this specific range
    vim.api.nvim_buf_clear_namespace(
      highlight.bufnr,
      namespace_id,
      highlight.start_line,
      highlight.end_line + 1
    )
    highlights[selection_key] = nil
  end
end

function M.clear_all()
  -- Clear namespace in all buffers
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(buf) then
      vim.api.nvim_buf_clear_namespace(buf, namespace_id, 0, -1)
    end
  end

  highlights = {}
  vim.notify('All highlights cleared', vim.log.levels.INFO)
end

return M
