-- bin/mv.lua  —  Move/rename files
local FS = _G.FS
local args = {...}
local opts = { force = false, verbose = false }
local targets = {}

for _, a in ipairs(args) do
    if a == "-f" or a == "--force" then opts.force = true
    elseif a == "-v" or a == "--verbose" then opts.verbose = true
    elseif a == "--help" then
        print("Usage: mv [OPTION]... SOURCE DEST")
        print("Rename SOURCE to DEST, or move SOURCE(s) to DIRECTORY.")
        return 0
    else
        table.insert(targets, a)
    end
end

if #targets < 2 then
    io.stderr:write("mv: missing operand\n")
    return 1
end

local dest = targets[#targets]
local sources = {}
for i = 1, #targets - 1 do
    table.insert(sources, targets[i])
end

if FS then dest = FS.normalize(dest) end

local isDestDir = fs.exists(dest) and fs.isDir(dest)
if #sources > 1 and not isDestDir then
    io.stderr:write("mv: target '" .. dest .. "' is not a directory\n")
    return 1
end

local ret = 0
for _, src in ipairs(sources) do
    local srcPath = src
    if FS then srcPath = FS.normalize(srcPath) end
    if not fs.exists(srcPath) then
        io.stderr:write("mv: cannot stat '" .. src .. "': No such file or directory\n")
        ret = 1
    else
        local targetPath = dest
        if isDestDir then
            targetPath = dest .. (dest:sub(-1) == "/" and "" or "/") .. fs.getName(srcPath)
        end
        if fs.exists(targetPath) and not opts.force then
            io.stderr:write("mv: '" .. dest .. "': File exists (use -f to overwrite)\n")
            ret = 1
        else
            fs.move(srcPath, targetPath)
            if opts.verbose then print("'" .. src .. "' -> '" .. targetPath .. "'") end
        end
    end
end
return ret
