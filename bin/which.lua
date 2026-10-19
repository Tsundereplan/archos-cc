-- bin/which.lua  —  Locate a command in PATH
-- Usage: which <command>
-- Searches /bin, /sbin, /usr/bin (and $PATH) for the named command.
-- Tries both <dir>/<cmd> and <dir>/<cmd>.lua.

local Kernel = _G.Kernel
local FS = _G.FS

local args = arg or {...}

-- -- Help -- --
if #args == 0 or args[1] == "--help" or args[1] == "-h" then
    print("Usage: which <command>")
    print("Locate a command file in PATH.")
    print("Searches PATH (" .. tostring(Kernel and Kernel.getEnv("PATH") or "/bin:/sbin:/usr/bin") .. ").")
    return #args == 0 and 1 or 0
end

local cmd = args[1]

-- -- Resolve PATH -- --
local pathStr = Kernel and Kernel.getEnv("PATH") or "/bin:/sbin:/usr/bin"

-- Build candidate directories list (skip empty entries)
local dirs = {}
for raw in tostring(pathStr):gmatch("[^:]+") do
    local d = raw
    if d == "." then
        d = Kernel and Kernel.getCwd() or "/"
    end
    table.insert(dirs, d)
end

-- -- Search -- --
local function try(p)
    if FS then return FS.exists(p) end
    return fs.exists(p)
end

for _, dir in ipairs(dirs) do
    -- Try literal <dir>/<cmd>
    local candidate = dir .. "/" .. cmd
    if try(candidate) then
        print(candidate)
        return 0
    end
    -- Try <dir>/<cmd>.lua (unless the user already gave an extension)
    if cmd:sub(-4) ~= ".lua" then
        candidate = candidate .. ".lua"
        if try(candidate) then
            print(candidate)
            return 0
        end
    end
end

-- -- Not found -- --
io.stderr:write("which: no " .. cmd .. " in PATH\n")
return 1
