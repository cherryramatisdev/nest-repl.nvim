local M = {}

function M.is_nest_project()
  local current_dir = vim.fn.expand('%:p:h')
  local nest_config = vim.fn.findfile('nest-cli.json', current_dir .. ';')
  return nest_config ~= ''
end

return M 