-- bin/cp.lua  —  Copy files
local FS = _G.FS
local args = {...}
local opts = { recursive = false, verbose = false, force = false }
local targets = {}

for _, a in ipairs(args) do
    if a == "-r" or a == "-R" or a == "--recursive" then opts.recursive = true
    elseif a == "-v" or a == "--verbose" then opts.verbose = true
    elseif a == "-f" or a == "--force" then opts.force = true
    elseif a == "-rf" or a == "-fr" then opts.recursive = true; opts.force = true
    elseif a == "--help" then
        print("Usage: cp [OPTION]... SOURCE DEST")
        print("  -r, -R, --recursive   copy directories recursively")
        print("  -v, --verbose         explain what is being done")
        print("  -f, --force           if file exists, overwrite")
        return 0
    else
        table.insert(targets, a)
    end
end

if #targets < 2 then
    io.stderr:write("cp: missing operand\n")
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
    io.stderr:write("cp: target '" .. dest .. "' is not a directory\n")
    return 1
end

local ret = 0
for _, src in ipairs(sources) do
    local srcPath = src
    if FS then srcPath = FS.normalize(srcPath) end
    if not fs.exists(srcPath) then
        io.stderr:write("cp: cannot stat '" .. src .. "': No such file or directory\n")
        ret = 1
    else
        local targetPath = dest
        if isDestDir then
            targetPath = dest .. (dest:sub(-1) == "/" and "" or "/") .. fs.getName(srcPath)
        end
        if fs.isDir(srcPath) and not opts.recursive then
            io.stderr:write("cp: omitting directory '" .. src .. "'\n")
            ret = 1
        else
            fs.copy(srcPath, targetPath)
            if opts.verbose then print("'" .. src .. "' -> '" .. targetPath .. "'") end
        end
    end
end
return ret
