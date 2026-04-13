-- Bootstrap plenary from lazy.nvim's install location, falling back to a clone
local plenary_path = vim.fn.stdpath('data') .. '/lazy/plenary.nvim'

if vim.fn.isdirectory(plenary_path) == 0 then
  plenary_path = '/tmp/plenary.nvim'
  if vim.fn.isdirectory(plenary_path) == 0 then
    vim.fn.system({
      'git', 'clone', '--depth=1',
      'https://github.com/nvim-lua/plenary.nvim',
      plenary_path,
    })
  end
end

vim.opt.rtp:prepend(vim.fn.getcwd()) -- lens.nvim itself
vim.opt.rtp:prepend(plenary_path)
