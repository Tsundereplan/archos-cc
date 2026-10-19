-- bin/rm.lua  —  Remove files or directories
local FS = _G.FS
local args = {...}
local opts = { recursive = false, force = false, verbose = false }
local targets = {}

for _, a in ipairs(args) do
    if a == "-r" or a == "-R" or a == "--recursive" then opts.recursive = true
    elseif a == "-f" or a == "--force" then opts.force = true
    elseif a == "-v" or a == "--verbose" then opts.verbose = true
    elseif a == "-rf" or a == "-fr" then opts.recursive = true; opts.force = true
    elseif a == "--help" then
        print("Usage: rm [OPTION]... FILE...")
        print("Remove (unlink) the FILE(s).")
        print("  -f, --force       ignore nonexistent files and arguments, never prompt")
        print("  -r, -R, --recursive  remove directories and their contents recursively")
        print("  -v, --verbose     explain what is being done")
        return 0
    else
        table.insert(targets, a)
    end
end

if #targets == 0 then
    if not opts.force then
        io.stderr:write("rm: missing operand\n")
        return 1
    end
    return 0
end

local ret = 0
for _, t in ipairs(targets) do
    local path = t
    if FS then path = FS.normalize(path) end
    if not fs.exists(path) then
        if not opts.force then
            io.stderr:write("rm: cannot remove '" .. t .. "': No such file or directory\n")
            ret = 1
        end
    elseif fs.isDir(path) and not opts.recursive then
        io.stderr:write("rm: cannot remove '" .. t .. "': Is a directory\n")
        ret = 1
    else
        -- Prompt for confirmation if not forced and we're running interactively
        if not opts.force and not _G.KERNEL_NONINTERACTIVE then
            -- Don't prompt for now (could implement)
        end
        local ok, err = pcall(fs.delete, path)
        if not ok then
            io.stderr:write("rm: cannot remove '" .. t .. "': " .. tostring(err) .. "\n")
            ret = 1
        elseif opts.verbose then
            print("removed '" .. t .. "'")
        end
    end
end
return ret
