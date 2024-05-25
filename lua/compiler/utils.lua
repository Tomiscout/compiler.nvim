--- ### Utils for compiler.nvim

local M = {}

---Recursively searches for files with the given name
-- in all directories under start_dir.
---@param start_dir string A dir path string.
---@param file_name string A file path string.
---@return table files If any, a tables of files. Otherwise, a Empty table.
function M.find_files(start_dir, file_name)
  local files = {}

  -- Create the find command with appropriate flags for recursive searching
  local find_command
  if string.sub(package.config, 1, 1) == "\\" then -- Windows
    find_command = string.format('powershell.exe -Command "Get-ChildItem -Path \\"%s\\" -Recurse -Filter \\"%s\\" -File -Exclude \\".git\\" -ErrorAction SilentlyContinue"', start_dir, file_name)
  else -- UNIX-like systems
    find_command = string.format('find "%s" -type d -name ".git" -prune -o -type f -name "%s" -print 2>/dev/null', start_dir, file_name)
  end

  -- Execute the find command and capture the output
  local pipe = io.popen(find_command, "r")
  if pipe then
    for file_path in pipe:lines() do
      table.insert(files, file_path)
      --print("Found file:", file_path)
    end
    pipe:close()
  end

  return files
end

---Search recursively, starting by the directory
-- of the entry_point file. Return files matching the pattern.
---@param entry_point string Entry point file of the program.
---@param pattern string File extension to search.
---@return string files_as_string Files separated by a space.
---@usage find_files_to_compile("/path/to/main.c", "*.c")
function M.find_files_to_compile(entry_point, pattern)
  local entry_point_dir = vim.fn.fnamemodify(entry_point, ":h")
  local files = M.find_files(entry_point_dir, pattern)
  local files_as_string = table.concat(files ," ")

  return files_as_string
end

---Parse the solution file and extract variables.
---@param file_path string Path of the solution file to read.
---@return table config A table like { {entry_point, ouptput, ..} .. }
-- The last table will only contain the solution executables like:
-- { "/path/to/executable", ... }
function M.parse_solution_file(file_path)
  local file = assert(io.open(file_path, "r"))
  local config = {}
  local executables = {}
  local current_entry = nil

  for line in file:lines() do
    if not (line:match("^%s*#") or line:match("^%s*$")) then
      local entry = line:match("%[([^%]]+)%]")
      if entry then
        current_entry = entry
        config[current_entry] = {}
      else
        local key, value = line:match("([^=]+)%s-=%s-(.+)")
        if key and value and current_entry then
          key = vim.trim(key)
          value = value:gsub("^%s*", ""):gsub(" *#.*", ""):gsub("^['\"](.-)['\"]$", "%1")  -- Remove inline comments and surrounding quotes

          if key == "entry_point" and value:find("^%$current_buffer") then
            value = string.gsub( -- Substitute $current_buffer by actual path
              value, "$current_buffer", vim.api.nvim_buf_get_name(0))
          end

          if string.find(key, "executable") then
            table.insert(executables, value)
          else
            config[current_entry][key] = value
          end
        end
      end
    end
  end

  file:close()
  config["executables"] = executables

  for key, value in pairs(config) do
    if type(value) == "table" and next(value) == nil then
      config[key] = nil
    end
  end

  return config
end

---Programatically require the backend for the current language.
---@return table|nil language The language backend.
-- If ./languages/<filetype>.lua doesn't exist, return nil.
function M.require_language(filetype)
  local local_path = debug.getinfo(1, "S").source:sub(2)
  local local_path_dir = local_path:match("(.*[/\\])")
  local module_file_path = M.os_path(local_path_dir .. "languages/" .. filetype .. ".lua")
  local success, language = pcall(dofile, module_file_path)

  if success then return language
  else
    -- local error = "Filetype \"" .. filetype .. "\" not supported by the compiler."
    -- vim.notify(error, vim.log.levels.INFO, { title = "Language unsupported" })
    return nil
  end
end

---Function that returns true if a file exists in physical storage
---@return boolean|nil exists true or false
function M.file_exists(filename)
  local stat = vim.loop.fs_stat(filename)
  return stat and stat.type == "file"
end

---Function that returns the path of the .solution file if exists in the current
-- working diectory root, or nil otherwise.
---@return string|nil path Path of the .solution file if exists in the current
-- working diectory root, or nil otherwise.
function M.get_solution_file()
  if M.file_exists(".solution.toml") then
    return  M.os_path(vim.fn.getcwd() .. "/.solution.toml")
  elseif M.file_exists(".solution") then
    return  M.os_path(vim.fn.getcwd() .. "/.solution")
  else
    return nil
  end
end

---Given a string, convert 'slash' to 'inverted slash' if on windows, and vice versa on UNIX.
-- Then return the resulting string.
---@param path string A path string.
---@return string|nil,nil path A path string formatted for the current OS.
function M.os_path(path)
  if path == nil then return nil end
  -- Get the platform-specific path separator
  local separator = string.sub(package.config, 1, 1)
  return string.gsub(path, '[/\\]', separator)
end

---Gets current buffer if it has a name, otherwise get last non_overseer buffer
function M.get_compiler_buffer()
  local buffer = vim.api.nvim_get_current_buf()
  if _G.last_non_overseer_buffer == nil or not vim.api.nvim_buf_is_loaded(_G.last_non_overseer_buffer) then
    return buffer
  end

  if vim.api.nvim_buf_get_name(buffer) == '' or vim.api.nvim_get_option_value("filetype", { buf = buffer }) == '' then
    buffer = _G.last_non_overseer_buffer
  end
  return buffer
end



return M
