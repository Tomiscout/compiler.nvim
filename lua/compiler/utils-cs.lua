local utils = require("compiler.utils")
local overseer = require("overseer")

local M = {}

function M.handle_csc_options(selected_option)
    local entry_point = utils.os_path(vim.fn.getcwd() .. "/Program.cs") -- working_directory/Program.cs
    local files = utils.find_files_to_compile(entry_point, "*.cs") -- *.cs files under entry_point_dir (recursively)
    local output_dir = utils.os_path(vim.fn.getcwd() .. "/bin/") -- working_directory/bin/
    local output = utils.os_path(vim.fn.getcwd() .. "/bin/Program.exe") -- working_directory/bin/program
    local arguments = "-warn:4 /debug" -- arguments can be overriden in .solution
    local final_message = "--task finished--"

    if selected_option == "csc_build_run" then
        local task =
            overseer.new_task(
            {
                name = "- C# compiler",
                strategy = {
                    "orchestrator",
                    tasks = {
                        {
                            "shell",
                            name = "- Build & run program → " .. entry_point,
                            cmd = "rm -f " ..
                                output ..
                                    " || true" .. -- clean
                                        " && mkdir -p " ..
                                            output_dir .. -- mkdir
                                                " && csc " ..
                                                    files ..
                                                        " -out:" ..
                                                            output ..
                                                                " " ..
                                                                    arguments .. -- compile bytecode
                                                                        " && mono " ..
                                                                            output .. -- run
                                                                                " ; echo " ..
                                                                                    entry_point .. -- echo
                                                                                        " ; echo '" ..
                                                                                            final_message .. "'"
                        }
                    }
                }
            }
        )
        task:start()
        vim.cmd("OverseerOpen")
    elseif selected_option == "csc_build" then
        local task =
            overseer.new_task(
            {
                name = "- C# compiler",
                strategy = {
                    "orchestrator",
                    tasks = {
                        {
                            "shell",
                            name = "- Build program → " .. entry_point,
                            cmd = "rm -f " ..
                                output ..
                                    " || true" .. -- clean
                                        " && mkdir -p " ..
                                            output_dir .. -- mkdir
                                                " && csc " ..
                                                    files ..
                                                        " -out:" ..
                                                            output ..
                                                                " " ..
                                                                    arguments .. -- compile bytecode
                                                                        " ; echo " ..
                                                                            entry_point .. -- echo
                                                                                " ; echo '" .. final_message .. "'"
                        }
                    }
                }
            }
        )
        task:start()
        vim.cmd("OverseerOpen")
    elseif selected_option == "csc_run" then
        local task =
            overseer.new_task(
            {
                name = "- C# compiler",
                strategy = {
                    "orchestrator",
                    tasks = {
                        {
                            "shell",
                            name = "- Run program → " .. entry_point,
                            cmd = "mono " ..
                                output .. -- run
                                    " ; echo " ..
                                        output .. -- echo
                                            " ; echo '" .. final_message .. "'"
                        }
                    }
                }
            }
        )
        task:start()
        vim.cmd("OverseerOpen")
    elseif selected_option == "csc_build_solution" then
        local entry_points
        local task = {}
        local tasks = {}
        local executables = {}

        -- if .solution file exists in working dir
        local solution_file = utils.get_solution_file()
        if solution_file then
            local config = utils.parse_solution_file(solution_file)

            for entry, variables in pairs(config) do
                if entry == "executables" then
                    goto continue
                end
                entry_point = utils.os_path(variables.entry_point)
                files = utils.find_files_to_compile(entry_point, "*.cs")
                output = utils.os_path(variables.output)
                output_dir = utils.os_path(output:match("^(.-[/\\])[^/\\]*$"))
                arguments = variables.arguments or arguments -- optional
                task = {
                    "shell",
                    name = "- Build program → " .. entry_point,
                    cmd = "rm -f " ..
                        output ..
                            " || true" .. -- clean
                                " && mkdir -p " ..
                                    output_dir .. -- mkdir
                                        " && csc " ..
                                            files ..
                                                " -out:" ..
                                                    output ..
                                                        " " ..
                                                            arguments .. -- compile bytecode
                                                                " && echo " ..
                                                                    entry_point .. -- echo
                                                                        " && echo '" .. final_message .. "'"
                }
                table.insert(tasks, task) -- store all the tasks we've created
                ::continue::
            end

            local solution_executables = config["executables"]
            if solution_executables then
                for entry, executable in pairs(solution_executables) do
                    task = {
                        "shell",
                        name = "- Run program → " .. executable,
                        cmd = "mono " ..
                            executable .. -- run
                                " && echo " ..
                                    executable .. -- echo
                                        " && echo '" .. final_message .. "'"
                    }
                    table.insert(executables, task) -- store all the executables we've created
                end
            end

            task =
                overseer.new_task(
                {
                    name = "- C# compiler",
                    strategy = {
                        "orchestrator",
                        tasks = {
                            tasks, -- Build all the programs in the solution in parallel
                            executables -- Then run the solution executable(s)
                        }
                    }
                }
            )
            task:start()
            vim.cmd("OverseerOpen")
        else -- If no .solution file
            -- Create a list of all entry point files in the working directory
            entry_points = utils.find_files(vim.fn.getcwd(), "Program.cs")

            for _, entry_point in ipairs(entry_points) do
                entry_point = utils.os_path(entry_point)
                files = utils.find_files_to_compile(entry_point, "*.cs")
                output_dir = utils.os_path(entry_point:match("^(.-[/\\])[^/\\]*$") .. "bin") -- entry_point/bin
                output = utils.os_path(output_dir .. "/program") -- entry_point/bin/program
                task = {
                    "shell",
                    name = "- Build program → " .. entry_point,
                    cmd = "rm -f " ..
                        output ..
                            " || true" .. -- clean
                                " && mkdir -p " ..
                                    output_dir .. -- mkdir
                                        " && csc " ..
                                            files ..
                                                " -out:" ..
                                                    output ..
                                                        " " ..
                                                            arguments .. -- compile bytecode
                                                                " && echo " ..
                                                                    entry_point .. -- echo
                                                                        " && echo '" .. final_message .. "'"
                }
                table.insert(tasks, task) -- store all the tasks we've created
            end

            task =
                overseer.new_task(
                {
                    -- run all tasks we've created in parallel
                    name = "- C# compiler",
                    strategy = {"orchestrator", tasks = tasks}
                }
            )
            task:start()
            vim.cmd("OverseerOpen")
        end
    end
end

return M
