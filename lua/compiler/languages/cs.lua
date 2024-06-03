--- C# language actions
local cs_utils = require("compiler.utils-cs")
local overseer = require("overseer")
local utils = require('compiler.utils')

local M = {}

local function getParentDirectoryPath(filePath)
    if filePath == nil then return nil end

    local parentPath = filePath:match("^(.*[/\\])[^/\\]*$")
    if parentPath then
        return parentPath:sub(1, -2)
    else
        return nil -- or '.'
    end
end

local buffer = utils.get_compiler_buffer()
local file_path = vim.api.nvim_buf_get_name(buffer)
local file_dir = getParentDirectoryPath(file_path)

local function find_parent_file_with_extension(start_dir, extension, maxDepth)
    local current_dir = start_dir
    if maxDepth == nil then
        maxDepth = 10
    end

    local depth = 0
    while current_dir and current_dir ~= "/" and depth < maxDepth do
        -- Check for .csproj files
        local f = io.popen('find "' .. current_dir .. '" -maxdepth 1 -type f -name "*.' .. extension .. '"')
        if f then
            local path = f:read("*l") -- Read the first matching file
            f:close()
            if path then
                return path
            end
        end

        -- Move up to the parent directory
        current_dir = current_dir:match("(.+)/[^/]*$")
        depth = depth + 1
    end
    return nil
end

local csproj_file = find_parent_file_with_extension(file_dir, "csproj")
local sln_file = find_parent_file_with_extension(getParentDirectoryPath(csproj_file), "sln", 2)

local separator = package.config:sub(1, 1) -- gets the directory separator used by the OS
local function extract_filename(path)
    local i = path:len()
    while i > 0 and path:sub(i, i) ~= separator do
        i = i - 1
    end
    return path:sub(i + 1)
end
local function adjustPathForOS(path)
    if separator == "\\" then -- Windows
        return path:gsub("/", "\\")
    else
        return path:gsub("\\", "/") -- POSIX systems
    end
end

if csproj_file ~= nil then
    M.header_title = extract_filename(csproj_file)
end

-- Parse solution

local function parse_solution_file(sln_file_path)
    local project_paths = {}
    local runnable_projects = {}
    local project_references_map = {}
    local sln_directory = getParentDirectoryPath(sln_file_path)

    -- Read and parse the solution file for project paths
    local sln_content = io.open(sln_file_path, "r")
    if not sln_content then
        return nil, "Unable to open the solution file."
    end
    for line in sln_content:lines() do
        local project_path = line:match('.*"(.*%.csproj)".*')
        if project_path then
            table.insert(project_paths, sln_directory .. separator .. adjustPathForOS(project_path))
        end
    end
    sln_content:close()

    -- Check each project file to determine if it is runnable and build the references map
    for _, path in ipairs(project_paths) do
        local full_path = io.open(path, "r")
        if not full_path then
            print("Warning: Unable to open project file at " .. path)
        else
            local content = full_path:read("*all")
            full_path:close()

            -- Determine if the project is runnable
            if
                content:match('<Project Sdk="Microsoft%.NET%.Sdk%.Web"') or
                    content:match('<Project Sdk="Microsoft%.NET%.Sdk%.Worker"') or
                    content:match("<OutputType>Exe</OutputType>")
             then
                runnable_projects[path] = true
            end

            -- Extract project references
            local references = {}
            for ref in content:gmatch('<ProjectReference Include="(.-)"') do
                table.insert(references, ref)
            end
            project_references_map[path] = references
        end
    end

    return project_paths, runnable_projects, project_references_map
end

local function generate_options(runnable)
    M.options = {} -- Clear previous options

    -- Build and run options for each runnable project
    for path, _ in pairs(runnable) do
        local filename = extract_filename(path)
        table.insert(M.options, {text = "Run " .. filename, value = "run_" .. path})
        table.insert(M.options, {text = "Build " .. filename, value = "build_" .. path})
        table.insert(M.options, {text = "", value = "separator"})
    end

    -- Global solution options
    if sln_file then
        table.insert(M.options, {text = "Build Solution", value = "solution_build"})
        table.insert(M.options, {text = "Clean Solution", value = "solution_clean"})
    end

    table.insert(M.options, {text = "", value = "separator"})
    table.insert(M.options, {text = "CSC Build and run program", value = "csc_build_run"})
    table.insert(M.options, {text = "CSC Build program", value = "csc_build"})
    table.insert(M.options, {text = "CSC Run program", value = "csc_run"})
    table.insert(M.options, {text = "CSC Build solution", value = "csc_build_solution"})

    -- Separator for visual clarity in the menu
    table.insert(M.options, {text = "", value = "separator"})
end

local function printTable(t, indent)
    indent = indent or ""
    for key, value in pairs(t) do
        if type(value) == "table" then
            print(indent .. key .. ":")
            printTable(value, indent .. "  ")
        else
            print(indent .. key .. ": " .. tostring(value))
        end
    end
end

--- Frontend  - options displayed on telescope

if sln_file ~= nil then
    local projects, runnable, references = parse_solution_file(sln_file)
--    printTable(projects)
--    printTable(runnable)
--    printTable(references)

    generate_options(runnable)
end

local function string_starts(String, Start)
    return string.sub(String, 1, string.len(Start)) == Start
end

--- Backend - overseer tasks performed on option selected
function M.action(selected_option)
    if string_starts(selected_option, "csc_") then
        cs_utils.handle_csc_options(selected_option)
        return
    end

    local final_message
    local cmd
    if selected_option:match("^run_") then
        local project_path = selected_option:sub(5)
        cmd = "dotnet run --project '" .. project_path .. "'"
        final_message = "Running " .. extract_filename(project_path)
    elseif selected_option:match("^build_") then
        local project_path = selected_option:sub(7)
        cmd = "dotnet build '" .. project_path .. "'"
        final_message = "Built " .. extract_filename(project_path)
    elseif selected_option == "solution_build" and sln_file then
        cmd = "dotnet build " .. sln_file
        final_message = "Solution built"
    elseif selected_option == "solution_clean" and sln_file then
        cmd = "dotnet clean " .. sln_file
        final_message = "Solution cleaned"
    end

    if cmd then
        local task =
            overseer.new_task(
            {
                name = "- C# compiler",
                strategy = {
                    "orchestrator",
                    tasks = {
                        {
                            "shell",
                            name = "- Dotnet command → " .. final_message,
                            cmd = cmd .. " && echo '" .. final_message .. "'"
                        }
                    }
                }
            }
        )
        task:start()
        vim.cmd("OverseerOpen")
    else
        print("Invalid option or missing project/solution files")
    end
end


return M
