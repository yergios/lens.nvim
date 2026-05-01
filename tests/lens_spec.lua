-- tests/lens_spec.lua
-- All positions passed to mock_visual use 1-based lnum/col, matching vim's getpos() format.
-- The lens module converts them: start_col = pos[3]-1, end_col = pos[3] (exclusive).

describe("lens.nvim", function()
  local lens
  local bufnr
  local ns
  local real_notify = vim.notify

  -- Return all extmarks in the test buffer under the lens namespace.
  local function get_marks()
    return vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { -1, -1 }, { details = true })
  end

  -- Call add_highlight_from_visual with mocked vim.fn.mode/getpos so we don't
  -- need to enter real visual mode. Positions are {0, lnum, col, 0} (getpos format).
  local function mock_visual_add(mode, start_pos, end_pos)
    local orig_mode = vim.fn.mode
    local orig_getpos = vim.fn.getpos
    vim.fn.mode = function()
      return mode
    end
    vim.fn.getpos = function(mark)
      if mark == "v" then
        return start_pos
      end
      return end_pos
    end
    lens.add_highlight_from_visual()
    vim.fn.mode = orig_mode
    vim.fn.getpos = orig_getpos
  end

  -- Silence vim.notify during a call and return whether a WARN was emitted.
  local function capture_warn(fn)
    local warned = false
    local orig = vim.notify
    vim.notify = function(_, level)
      if level == vim.log.levels.WARN then
        warned = true
      end
    end
    fn()
    vim.notify = orig
    return warned
  end

  before_each(function()
    vim.notify = function() end

    lens = require("lens")
    lens.setup({ setup_keymaps = false })
    lens.clear_all()

    bufnr = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_current_buf(bufnr)
    vim.api.nvim_win_set_buf(0, bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {
      "Hello world", -- 0-indexed line 0
      "foo bar baz", -- 0-indexed line 1
      "line three", -- 0-indexed line 2
      "four five six", -- 0-indexed line 3
    })

    ns = vim.api.nvim_get_namespaces()["lens"]
    assert.is_not_nil(ns)
  end)

  after_each(function()
    lens.clear_all()
    if vim.api.nvim_buf_is_valid(bufnr) then
      vim.api.nvim_buf_delete(bufnr, { force = true })
    end
    vim.notify = real_notify
  end)

  -- ───────────────────────────────────────────────
  -- Character visual mode (v)
  -- ───────────────────────────────────────────────
  describe("character visual mode (v)", function()
    it("adds a highlight for a single-line selection", function()
      -- "Hello" → line 1, cols 1–5 (1-based)
      mock_visual_add("v", { 0, 1, 1, 0 }, { 0, 1, 5, 0 })
      assert.equals(1, #get_marks())
    end)

    it("places the extmark at the correct start position", function()
      mock_visual_add("v", { 0, 1, 3, 0 }, { 0, 1, 7, 0 })
      local marks = get_marks()
      assert.equals(1, #marks)
      assert.equals(0, marks[1][2]) -- 0-indexed line
      assert.equals(2, marks[1][3]) -- 0-indexed col (3-1=2)
    end)

    it("does not highlight when called outside visual mode", function()
      local warned = capture_warn(function()
        lens.add_highlight_from_visual()
      end)
      assert.is_true(warned)
      assert.equals(0, #get_marks())
    end)
  end)

  -- ───────────────────────────────────────────────
  -- V-line mode (V)
  -- ───────────────────────────────────────────────
  describe("V-line mode (V)", function()
    it("adds a highlight covering an entire single line", function()
      mock_visual_add("V", { 0, 2, 1, 0 }, { 0, 2, 1, 0 })
      assert.equals(1, #get_marks())
    end)

    it("adds one extmark per line for a multi-line V-line selection", function()
      -- Lines 1–3: 3 extmarks
      mock_visual_add("V", { 0, 1, 1, 0 }, { 0, 3, 1, 0 })
      assert.equals(3, #get_marks())
    end)

    it("highlights only actual line characters, not the buffer width", function()
      -- "foo bar baz" is 11 chars; highlight should end at col 11 with no hl_eol fill.
      mock_visual_add("V", { 0, 2, 1, 0 }, { 0, 2, 1, 0 })
      local marks = get_marks()
      assert.equals(1, #marks)
      local details = marks[1][4]
      assert.equals(marks[1][2], details.end_row) -- same line, not next line
      assert.equals(11, details.end_col)
      assert.is_not_true(details.hl_eol)
    end)

    it("each line in a multi-line V selection ends at its own text length", function()
      -- Lines 0–2: "Hello world" (11), "foo bar baz" (11), "line three" (10)
      mock_visual_add("V", { 0, 1, 1, 0 }, { 0, 3, 1, 0 })
      local marks = get_marks()
      assert.equals(3, #marks)
      local lengths = { 11, 11, 10 }
      for i, m in ipairs(marks) do
        local details = m[4]
        assert.equals(m[2], details.end_row)
        assert.equals(lengths[i], details.end_col)
        assert.is_not_true(details.hl_eol)
      end
    end)
  end)

  -- ───────────────────────────────────────────────
  -- Multi-line character selection
  -- ───────────────────────────────────────────────
  describe("multi-line character selection", function()
    it("adds one extmark per line for a two-line selection", function()
      -- Line 1 col 7 → line 2 col 3
      mock_visual_add("v", { 0, 1, 7, 0 }, { 0, 2, 3, 0 })
      assert.equals(2, #get_marks())
    end)

    it("adds one extmark per line for a four-line selection", function()
      mock_visual_add("v", { 0, 1, 1, 0 }, { 0, 4, 4, 0 })
      assert.equals(4, #get_marks())
    end)
  end)

  -- ───────────────────────────────────────────────
  -- Visual block mode (^V) — always full-line
  -- ───────────────────────────────────────────────
  describe("visual block mode (^V)", function()
    it("adds one extmark per line in the block", function()
      mock_visual_add("\22", { 0, 1, 1, 0 }, { 0, 3, 5, 0 })
      assert.equals(3, #get_marks())
    end)

    it("each extmark starts at column 0 regardless of block columns", function()
      mock_visual_add("\22", { 0, 1, 3, 0 }, { 0, 3, 7, 0 })
      local marks = get_marks()
      for _, m in ipairs(marks) do
        assert.equals(0, m[3])
      end
    end)

    it("each extmark extends to the end of its line and fills the visual width", function()
      mock_visual_add("\22", { 0, 1, 2, 0 }, { 0, 3, 5, 0 })
      local marks = get_marks()
      -- The EOL sentinel stores end_col=0 on the next line; hl_eol fills past text.
      for _, m in ipairs(marks) do
        local details = m[4]
        assert.equals(m[2] + 1, details.end_row) -- next line
        assert.equals(0, details.end_col)
        assert.is_true(details.hl_eol)
      end
    end)

    it("narrow and wide block on the same lines produce identical extmarks", function()
      mock_visual_add("\22", { 0, 2, 1, 0 }, { 0, 3, 2, 0 }) -- narrow: cols 1-2
      local narrow = get_marks()
      lens.clear_all()
      mock_visual_add("\22", { 0, 2, 1, 0 }, { 0, 3, 11, 0 }) -- wide: cols 1-11
      local wide = get_marks()

      assert.equals(#narrow, #wide)
      for i = 1, #narrow do
        assert.equals(narrow[i][2], wide[i][2]) -- same start line
        assert.equals(narrow[i][3], wide[i][3]) -- same start col (0)
        assert.equals(narrow[i][4].end_row, wide[i][4].end_row)
        assert.equals(narrow[i][4].end_col, wide[i][4].end_col)
      end
    end)

    it("single-line block highlights the full line", function()
      mock_visual_add("\22", { 0, 2, 3, 0 }, { 0, 2, 7, 0 })
      local marks = get_marks()
      assert.equals(1, #marks)
      assert.equals(0, marks[1][3]) -- start col 0
      assert.equals(marks[1][2] + 1, marks[1][4].end_row)
      assert.equals(0, marks[1][4].end_col)
    end)
  end)

  -- ───────────────────────────────────────────────
  -- Multiple highlights
  -- ───────────────────────────────────────────────
  describe("multiple highlights", function()
    it("can add two non-overlapping highlights on different lines", function()
      mock_visual_add("v", { 0, 1, 1, 0 }, { 0, 1, 5, 0 }) -- line 0
      mock_visual_add("v", { 0, 2, 1, 0 }, { 0, 2, 3, 0 }) -- line 1
      assert.equals(2, #get_marks())
    end)

    it("can add three V-line highlights on separate lines", function()
      mock_visual_add("V", { 0, 1, 1, 0 }, { 0, 1, 1, 0 })
      mock_visual_add("V", { 0, 3, 1, 0 }, { 0, 3, 1, 0 })
      mock_visual_add("V", { 0, 4, 1, 0 }, { 0, 4, 1, 0 })
      assert.equals(3, #get_marks())
    end)
  end)

  -- ───────────────────────────────────────────────
  -- Mode after adding a highlight
  -- ───────────────────────────────────────────────
  describe("mode after adding a highlight", function()
    it("returns to normal mode after adding a highlight from visual mode", function()
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      -- Enter real visual mode and select the first word
      vim.api.nvim_feedkeys("viw", "x", true)
      assert.equals("v", vim.fn.mode())
      lens.add_highlight_from_visual()
      -- Flush the queued <Esc>
      vim.api.nvim_feedkeys("", "x", false)
      assert.equals("n", vim.fn.mode())
    end)
  end)

  -- ───────────────────────────────────────────────
  -- Removing highlights
  -- ───────────────────────────────────────────────
  describe("remove_highlight_at_cursor", function()
    -- "Hello" on line 0: start_col=0, end_col=5 (exclusive)
    before_each(function()
      lens.add_highlight(bufnr, 0, 0, 0, 5, "hello_key")
    end)

    it("removes the highlight when cursor is at the first column", function()
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      lens.remove_highlight_at_cursor()
      assert.equals(0, #get_marks())
    end)

    it("removes the highlight when cursor is in the middle", function()
      vim.api.nvim_win_set_cursor(0, { 1, 2 })
      lens.remove_highlight_at_cursor()
      assert.equals(0, #get_marks())
    end)

    it("removes the highlight when cursor is at the last included column", function()
      vim.api.nvim_win_set_cursor(0, { 1, 4 }) -- col 4 < end_col 5
      lens.remove_highlight_at_cursor()
      assert.equals(0, #get_marks())
    end)

    it("does not remove when cursor is at the exclusive end column", function()
      vim.api.nvim_win_set_cursor(0, { 1, 5 }) -- col 5 == end_col, out of range
      lens.remove_highlight_at_cursor()
      assert.equals(1, #get_marks())
    end)

    it("does nothing and warns when cursor is on a line with no highlight", function()
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      local warned = capture_warn(function()
        lens.remove_highlight_at_cursor()
      end)
      assert.is_true(warned)
      assert.equals(1, #get_marks()) -- original still present
    end)

    it("only removes the highlight under the cursor, leaving others intact", function()
      -- Add a second highlight on a different line so range-clear cannot affect it
      lens.add_highlight(bufnr, 2, 0, 2, 4, "line3_key")
      assert.equals(2, #get_marks())

      vim.api.nvim_win_set_cursor(0, { 1, 2 }) -- over 'hello_key'
      lens.remove_highlight_at_cursor()

      local line3_marks = vim.api.nvim_buf_get_extmarks(
        bufnr,
        ns,
        { 2, 0 },
        { 2, -1 },
        { details = true }
      )
      assert.equals(1, #line3_marks)
    end)
  end)

  -- ───────────────────────────────────────────────
  -- Removing a multi-line highlight from any line
  -- ───────────────────────────────────────────────
  describe("remove multi-line highlight", function()
    before_each(function()
      -- Lines 0–2, cols 0–5 on last line
      lens.add_highlight(bufnr, 0, 0, 2, 5, "multi_key")
    end)

    it("removes when cursor is on the first line", function()
      vim.api.nvim_win_set_cursor(0, { 1, 0 })
      lens.remove_highlight_at_cursor()
      assert.equals(0, #get_marks())
    end)

    it("removes when cursor is on a middle line", function()
      vim.api.nvim_win_set_cursor(0, { 2, 0 })
      lens.remove_highlight_at_cursor()
      assert.equals(0, #get_marks())
    end)

    it("removes when cursor is on the last line within the column range", function()
      vim.api.nvim_win_set_cursor(0, { 3, 4 }) -- col 4 < end_col 5
      lens.remove_highlight_at_cursor()
      assert.equals(0, #get_marks())
    end)

    it("does not remove when cursor is on the last line past the column range", function()
      vim.api.nvim_win_set_cursor(0, { 3, 5 }) -- col 5 == end_col, out of range
      lens.remove_highlight_at_cursor()
      assert.equals(3, #get_marks()) -- all three line extmarks remain
    end)
  end)

  -- ───────────────────────────────────────────────
  -- <leader>l in normal mode over no highlight
  -- ───────────────────────────────────────────────
  describe("<leader>l equivalent in normal mode", function()
    it("warns and changes nothing when there are no highlights", function()
      local warned = capture_warn(function()
        lens.remove_highlight_at_cursor()
      end)
      assert.is_true(warned)
      assert.equals(0, #get_marks())
    end)

    it("does not error when there are no highlights", function()
      assert.has_no.errors(function()
        lens.remove_highlight_at_cursor()
      end)
    end)

    it("warns and changes nothing when cursor is between highlights", function()
      lens.add_highlight(bufnr, 0, 0, 0, 5, "k1")
      lens.add_highlight(bufnr, 2, 0, 2, 5, "k2")
      vim.api.nvim_win_set_cursor(0, { 2, 0 }) -- line 1 (0-indexed), no highlight
      local warned = capture_warn(function()
        lens.remove_highlight_at_cursor()
      end)
      assert.is_true(warned)
      assert.equals(2, #get_marks())
    end)
  end)

  -- ───────────────────────────────────────────────
  -- clear_all (<leader>L)
  -- ───────────────────────────────────────────────
  describe("clear_all", function()
    it("clears all highlights in the current buffer", function()
      mock_visual_add("v", { 0, 1, 1, 0 }, { 0, 1, 5, 0 })
      mock_visual_add("V", { 0, 3, 1, 0 }, { 0, 3, 1, 0 })
      assert.equals(2, #get_marks())
      lens.clear_all()
      assert.equals(0, #get_marks())
    end)

    it("does not error when there are no highlights", function()
      assert.has_no.errors(function()
        lens.clear_all()
      end)
    end)

    it("clears highlights across multiple buffers", function()
      local buf2 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "another buffer" })
      lens.add_highlight(buf2, 0, 0, 0, 7, "buf2_key")

      mock_visual_add("v", { 0, 1, 1, 0 }, { 0, 1, 5, 0 })

      lens.clear_all()

      local m1 = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 0 }, { -1, -1 }, {})
      local m2 = vim.api.nvim_buf_get_extmarks(buf2, ns, { 0, 0 }, { -1, -1 }, {})
      assert.equals(0, #m1)
      assert.equals(0, #m2)

      vim.api.nvim_buf_delete(buf2, { force = true })
    end)

    it("after clear_all, adding new highlights works normally", function()
      mock_visual_add("v", { 0, 1, 1, 0 }, { 0, 1, 5, 0 })
      lens.clear_all()
      mock_visual_add("v", { 0, 2, 1, 0 }, { 0, 2, 3, 0 })
      assert.equals(1, #get_marks())
    end)
  end)

  -- ───────────────────────────────────────────────
  -- Edge cases
  -- ───────────────────────────────────────────────
  describe("edge cases", function()
    it("does not add a duplicate for the same selection", function()
      mock_visual_add("v", { 0, 1, 1, 0 }, { 0, 1, 5, 0 })
      mock_visual_add("v", { 0, 1, 1, 0 }, { 0, 1, 5, 0 }) -- identical
      assert.equals(1, #get_marks())
    end)

    it("notifies when a duplicate selection is attempted", function()
      mock_visual_add("v", { 0, 1, 1, 0 }, { 0, 1, 5, 0 })
      local notified = false
      local orig = vim.notify
      vim.notify = function()
        notified = true
      end
      mock_visual_add("v", { 0, 1, 1, 0 }, { 0, 1, 5, 0 })
      vim.notify = orig
      assert.is_true(notified)
    end)

    it("handles a reversed selection (anchor after cursor)", function()
      -- Selecting leftward: start_pos col > end_pos col
      mock_visual_add("v", { 0, 1, 5, 0 }, { 0, 1, 1, 0 })
      assert.equals(1, #get_marks())
    end)

    it("handles a single-character selection", function()
      mock_visual_add("v", { 0, 1, 1, 0 }, { 0, 1, 1, 0 })
      assert.equals(1, #get_marks())
    end)

    it("handles a selection at the very end of the buffer", function()
      -- "six" at end of last line: line 4, cols 11–13
      mock_visual_add("v", { 0, 4, 11, 0 }, { 0, 4, 13, 0 })
      assert.equals(1, #get_marks())
    end)

    it("handles a V-line selection of the whole buffer", function()
      mock_visual_add("V", { 0, 1, 1, 0 }, { 0, 4, 1, 0 })
      assert.equals(4, #get_marks())
      lens.clear_all()
      assert.equals(0, #get_marks())
    end)

    it("removing one same-line highlight leaves the other intact", function()
      lens.add_highlight(bufnr, 0, 0, 0, 3, "word1")
      lens.add_highlight(bufnr, 0, 6, 0, 11, "word2")
      assert.equals(2, #get_marks())

      vim.api.nvim_win_set_cursor(0, { 1, 1 }) -- over 'word1' (cols 0–2)
      lens.remove_highlight_at_cursor()

      -- Only word1 is removed; word2's extmark on the same line survives.
      assert.equals(1, #get_marks())
      local word2_marks = vim.api.nvim_buf_get_extmarks(bufnr, ns, { 0, 6 }, { 0, 11 }, {})
      assert.equals(1, #word2_marks)
    end)

    it("remove_highlight_at_cursor does not affect a different buffer", function()
      local buf2 = vim.api.nvim_create_buf(false, true)
      vim.api.nvim_buf_set_lines(buf2, 0, -1, false, { "other buffer line" })
      lens.add_highlight(buf2, 0, 0, 0, 5, "buf2_hl")

      -- Highlight in current buffer at same position
      lens.add_highlight(bufnr, 0, 0, 0, 5, "buf1_hl")

      vim.api.nvim_win_set_cursor(0, { 1, 2 }) -- current buf = bufnr
      lens.remove_highlight_at_cursor()

      -- bufnr highlight gone
      assert.equals(0, #get_marks())
      -- buf2 highlight untouched
      local m2 = vim.api.nvim_buf_get_extmarks(buf2, ns, { 0, 0 }, { -1, -1 }, {})
      assert.equals(1, #m2)

      vim.api.nvim_buf_delete(buf2, { force = true })
    end)
  end)
end)
