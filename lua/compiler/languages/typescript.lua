--- Typescript language actions

local M = {}

--- Frontend  - options displayed on telescope
M.options = {
  { text = "1 - Run this file", value = "option1" },
  { text = "2 - Run program",   value = "option2" },
  { text = "3 - Run solution",  value = "option3" },
  { text = "4 - Run Makefile",  value = "option4" }
}

--- Backend - overseer tasks performed on option selected
function M.action(selected_option)
  local utils = require("compiler.utils")
  local overseer = require("overseer")
  local current_file = vim.fn.expand('%:p')                                  -- current file
  local entry_point = utils.os_path(vim.fn.getcwd() .. "/src/main.ts")       -- working_directory/main.ts
  local output_dir = utils.os_path(vim.fn.getcwd() .. "/dist/")              -- working_directory/dist/
  local arguments = "--outDir " .. output_dir
  local final_message = "--task finished--"

  if selected_option == "option1" then
    local current_file_js = output_dir .. vim.fn.fnamemodify(current_file, ":t:r") .. ".js"
    local task = overseer.new_task({
      name = "- Typescript transpiler",
      strategy = { "orchestrator",
        tasks = {{ "shell", name = "- Run this file → " .. current_file,
          cmd = "tsc " .. arguments .. " " .. current_file ..                -- transpile to js
                " && node " .. current_file_js ..                            -- run program (interpreted)
                " && echo " .. current_file ..                               -- echo
                " && echo '" .. final_message .. "'"
        },},},})
    task:start()
    vim.cmd("OverseerOpen")
  elseif selected_option == "option2" then
    local entry_point_js = output_dir .. vim.fn.fnamemodify(entry_point, ":t:r") .. ".js"
    local task = overseer.new_task({
      name = "- Typescript transpiler",
      strategy = { "orchestrator",
        tasks = {{ "shell", name = "- Run this program → " .. entry_point,
          cmd = "tsc " .. arguments .. " " .. entry_point ..                 -- transpile to js
                " && node " .. entry_point_js ..                             -- run program (interpreted)
                " && echo " .. current_file ..                               -- echo
                " && echo '" .. final_message .. "'"
        },},},})
    task:start()
    vim.cmd("OverseerOpen")
  elseif selected_option == "option3" then
    local entry_point_js
    local entry_points
    local task = {}
    local tasks = {}
    local executables = {}

    -- if .solution file exists in working dir
    local solution_file = utils.get_solution_file()
    if solution_file then
      local config = utils.parse_solution_file(solution_file)

      for entry, variables in pairs(config) do
        if entry == "executables" then goto continue end
        entry_point = utils.os_path(variables.entry_point)
        output = utils.os_path(variables.output)
        output_dir = vim.fn.fnamemodify(output, ":h") -- remove filename if any
        entry_point_js = output_dir .. "/" .. vim.fn.fnamemodify(entry_point, ":t:r") .. ".js"
        arguments = variables.arguments or "--outDir " .. output_dir -- optional
        task = { "shell", name = "- Run program → " .. entry_point,
          cmd = "tsc " .. arguments .. " " .. entry_point ..                 -- transpile to js
                " && node " .. entry_point_js ..                             -- run program (interpreted)
                " && echo " .. current_file ..                               -- echo
                " && echo '" .. final_message .. "'"
        }
        table.insert(tasks, task) -- store all the tasks we've created
        ::continue::
      end

      local solution_executables = config["executables"]
      if solution_executables then
        for entry, executable in pairs(solution_executables) do
          task = { "shell", name = "- Run program → " .. executable,
            cmd = executable ..                                              -- run
                  " && echo " .. executable ..                               -- echo
                  " && echo '" .. final_message .. "'"
          }
          table.insert(executables, task) -- store all the executables we've created
        end
      end

      task = overseer.new_task({
        name = "- Typescript transpiler", strategy = { "orchestrator",
          tasks = {
            tasks,        -- Build all the programs in the solution in parallel
            executables   -- Then run the solution executable(s)
          }}})
      task:start()
      vim.cmd("OverseerOpen")

    else -- If no .solution file
      -- Create a list of all entry point files in the working directory
      entry_points = utils.find_files(vim.fn.getcwd(), "main.ts")
      for _, entry_point in ipairs(entry_points) do
        entry_point = utils.os_path(entry_point)
        entry_point_js = output_dir .. vim.fn.fnamemodify(entry_point, ":t:r") .. ".js"
        task = { "shell", name = "- Build program → " .. entry_point,
          cmd = "tsc " .. arguments .. " " .. entry_point ..                 -- transpile to js
                " && node " .. entry_point_js ..                             -- run program (interpreted)
                " && echo " .. entry_point ..                               -- echo
                " && echo '" .. final_message .. "'"
        }
        table.insert(tasks, task) -- store all the tasks we've created
      end

      task = overseer.new_task({ -- run all tasks we've created in parallel
        name = "- Typescript transpiler", strategy = { "orchestrator", tasks = tasks }
      })
      task:start()
      vim.cmd("OverseerOpen")
    end
  elseif selected_option == "option4" then
    require("compiler.languages.make").run_makefile()                        -- run
  end

end

return M