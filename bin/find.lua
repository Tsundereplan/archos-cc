-- bin/find.lua  —  Search for files in a directory hierarchy
-- Usage: find [PATH] [EXPRESSION]
-- Expression primaries:
--   -name PATTERN    match filename against Lua pattern
--   -type f          regular files only
--   -type d          directories only
--   -print           print path (default action)
--   --help           show help
-- Default PATH is "."; default action is -print.

local FS = _G.FS
local args = arg or {...}

-- -- Argument parsing -- --
-- find syntax is unusual: tokens are primaries that may take args.
-- We parse: first non-option token is the path; the rest form the expression.
local path = nil
local namePattern = nil
local typeFilter = nil   -- "f" | "d" | nil
local doPrint = true

local i = 1
-- Pull path (first token that doesn't start with -)
if #args > 0 and args[1]:sub(1, 1) ~= "-" then
    path = args[1]
    i = 2
end

while i <= #args do
    local a = args[i]
    if a == "--help" or a == "-h" then
        print("Usage: find [PATH] [EXPRESSION]")
        print("  -name PATTERN   match filename (Lua pattern)")
        print("  -type f         files only")
        print("  -type d         directories only")
        print("  -print          print matching paths (default)")
        return 0
    elseif a == "-name" then
        i = i + 1
        namePattern = args[i]
    elseif a == "-type" then
        i = i + 1
        local t = args[i]
        if t ~= "f" and t ~= "d" then
            io.stderr:write("find: unknown type '" .. tostring(t) .. "'\n")
            return 1
        end
        typeFilter = t
    elseif a == "-print" then
        doPrint = true
    elseif a:sub(1, 1) == "-" then
        io.stderr:write("find: unknown primary '" .. a .. "'\n")
        return 1
    elseif path == nil then
        -- Second positional after path? treat as another path (ignored, first wins)
        path = a
    else
        io.stderr:write("find: unexpected argument '" .. a .. "'\n")
        return 1
    end
    i = i + 1
end

if path == nil then path = "." end

-- -- Resolve the path -- --
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
local function getName(p)
    -- Strip trailing slashes and take last segment
    local n = p:gsub("/+$", "")
    n = n:match("([^/]+)$") or n
    return n
end

local root = FS and FS.normalize(path) or path

if not exists(root) then
    io.stderr:write("find: '" .. path .. "': No such file or directory\n")
    return 1
end

-- -- Match function -- --
local function matches(p, isDir)
    -- Type filter
    if typeFilter == "f" and isDir then return false end
    if typeFilter == "d" and not isDir then return false end
    -- Name filter
    if namePattern then
        local name = getName(p)
        if not name:find(namePattern) then return false end
    end
    return true
end

-- -- Walk -- --
local matchCount = 0
local function walk(p)
    local isD = isDir(p)
    -- Test the entry itself
    if matches(p, isD) then
        if doPrint then print(p) end
        matchCount = matchCount + 1
    end
    if isD then
        local items = listDir(p)
        table.sort(items)
        for _, n in ipairs(items) do
            local sep = (p:sub(-1) == "/") and "" or "/"
            walk(p .. sep .. n)
        end
    end
end

walk(root)

return matchCount > 0 and 0 or 1
