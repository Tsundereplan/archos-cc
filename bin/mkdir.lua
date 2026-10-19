-- bin/mkdir.lua  —  Make directories
local FS = _G.FS
local args = {...}
local opts = { parents = false, verbose = false }
local targets = {}

for _, a in ipairs(args) do
    if a == "-p" or a == "--parents" then opts.parents = true
    elseif a == "-v" or a == "--verbose" then opts.verbose = true
    elseif a == "--help" then
        print("Usage: mkdir [OPTION]... DIRECTORY...")
        print("Create the DIRECTORY(ies), if they do not already exist.")
        print("  -p, --parents   no error if existing, make parent directories as needed")
        print("  -v, --verbose   print a message for each created directory")
        return 0
    else
        table.insert(targets, a)
    end
end

if #targets == 0 then
    io.stderr:write("mkdir: missing operand\n")
    return 1
end

local Kernel = _G.Kernel
local ret = 0
for _, t in ipairs(targets) do
    local path = t
    if FS then path = FS.normalize(path) end
    if fs.exists(path) then
        if not opts.parents then
            io.stderr:write("mkdir: cannot create directory '" .. t .. "': File exists\n")
            ret = 1
        end
    else
        if opts.parents then
            -- Create intermediate dirs
            local parts = {}
            for p in path:gmatch("[^/]+") do table.insert(parts, p) end
            local cur = ""
            for _, p in ipairs(parts) do
                cur = cur .. "/" .. p
                if not fs.exists(cur) then
                    fs.makeDir(cur)
                    if opts.verbose then print("mkdir: created directory '" .. cur .. "'") end
                end
            end
        else
            -- Only create if parent exists
            local parent = path:match("^(.*)/[^/]+$") or "/"
            if parent ~= "" and not fs.exists(parent) then
                io.stderr:write("mkdir: cannot create directory '" .. t .. "': No such file or directory\n")
                ret = 1
            else
                fs.makeDir(path)
                if opts.verbose then print("mkdir: created directory '" .. path .. "'") end
            end
        end
    end
end
return ret
