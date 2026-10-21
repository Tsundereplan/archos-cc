-- bin/tree.lua  —  List contents of directories in a tree-like format
-- Usage: tree [OPTIONS] [DIR]
-- Options:
--   -L N   max display depth (default 3)
--   -a     show hidden files (starting with .)
--   -d     directories only
--   --help show help

local FS = _G.FS
local Kernel = _G.Kernel
local args = arg or {...}

-- -- Option parsing -- --
local maxDepth = 3
local showHidden = false
local dirsOnly = false
local target = nil

local i = 1
while i <= #args do
    local a = args[i]
    if a == "--help" or a == "-h" then
        print("Usage: tree [OPTIONS] [DIR]")
        print("  -L N   max display depth (default 3)")
        print("  -a     show hidden files")
        print("  -d     directories only")
        return 0
    elseif a == "-L" then
        i = i + 1
        local n = tonumber(args[i])
        if not n then
            io.stderr:write("tree: invalid depth: '" .. tostring(args[i]) .. "'\n")
            return 1
        end
        maxDepth = n
    elseif a:sub(1, 2) == "-L" and #a > 2 then
        local n = tonumber(a:sub(3))
        if not n then
            io.stderr:write("tree: invalid depth: '" .. a:sub(3) .. "'\n")
            return 1
        end
        maxDepth = n
    elseif a:sub(1, 1) == "-" and #a > 1 then
        for j = 2, #a do
            local c = a:sub(j, j)
            if c == "a" then showHidden = true
            elseif c == "d" then dirsOnly = true
            else
                io.stderr:write("tree: invalid option -- '" .. c .. "'\n")
                return 1
            end
        end
    else
        target = a
    end
    i = i + 1
end

-- -- Resolve target -- --
if not target then target = "." end
local real
if FS then
    real = FS.normalize(target)
else
    real = target
end

local function exists(p)
    if FS then return FS.exists(p) end
    return fs.exists(p)
end
local function isDir(p)
    if FS then return FS.isDir(p) end
    return fs.isDir(p)
end
local function listDir(p)
    if FS then return FS.list(p) or {} end
    return fs.list(p)
end

if not exists(real) then
    io.stderr:write("tree: " .. target .. ": No such file or directory\n")
    return 1
end

-- -- Walker -- --
-- Tries _G.FS.tree when no special flags are set; otherwise uses a custom
-- walker so we can filter hidden files and skip non-dirs.
local dirCount = 0
local fileCount = 0

local function shouldShow(name)
    if not showHidden and name:sub(1, 1) == "." then return false end
    return true
end

local function customWalk(rootPath, depth, prefix, out)
    if depth > maxDepth then return end
    local items = listDir(rootPath)
    -- Filter
    local filtered = {}
    for _, n in ipairs(items) do
        if shouldShow(n) then
            -- If dirsOnly, skip files entirely (but keep dirs)
            if not dirsOnly or isDir(rootPath .. (rootPath:sub(-1) == "/" and "" or "/") .. n) then
                table.insert(filtered, n)
            end
        end
    end
    table.sort(filtered)
    for idx, name in ipairs(filtered) do
        local sep = (rootPath:sub(-1) == "/") and "" or "/"
        local child = rootPath .. sep .. name
        local last = (idx == #filtered)
        local branch = last and "+-- " or "+-- "
        local isD = isDir(child)
        -- Colorize
        if term.isColor() then
            if isD then term.setTextColor(colors.lightBlue)
            elseif name:sub(-4) == ".lua" then term.setTextColor(colors.green)
            else term.setTextColor(colors.white) end
        end
        table.insert(out, prefix .. branch .. name .. (isD and "/" or ""))
        if term.isColor() then term.setTextColor(colors.white) end
        if isD then
            dirCount = dirCount + 1
            local nextPrefix = prefix .. (last and "    " or "|   ")
            customWalk(child, depth + 1, nextPrefix, out)
        else
            fileCount = fileCount + 1
        end
    end
end

local out = {}
-- Print the root first (FS.tree puts the root as the first line)
table.insert(out, real)

if not showHidden and not dirsOnly and FS and FS.tree then
    -- Use the kernel-provided FS.tree for the default case
    out = FS.tree(real, maxDepth)
    -- Count entries (approximate): the first line is the root; every line that
    -- ends with "/" or contains a "|"/"+" referring to a dir is counted.
    -- FS.tree doesn't give us dir/file counts, so we still walk to compute them.
    local function countWalk(p, depth)
        if depth > maxDepth then return end
        local items = listDir(p)
        for _, n in ipairs(items) do
            if shouldShow(n) then
                local sep = (p:sub(-1) == "/") and "" or "/"
                local child = p .. sep .. n
                if isDir(child) then
                    dirCount = dirCount + 1
                    countWalk(child, depth + 1)
                else
                    fileCount = fileCount + 1
                end
            end
        end
    end
    countWalk(real, 1)
else
    customWalk(real, 1, "", out)
end

-- -- Print -- --
for _, line in ipairs(out) do
    print(line)
end

print()
print(string.format("%d directories, %d files", dirCount, fileCount))
return 0
