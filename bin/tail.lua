-- bin/tail.lua  —  Print the last lines of files
-- Usage: tail [OPTIONS] [FILE...]
-- Options:
--   -n N   number of lines from the end (default 10)
--   --help show help

local FS = _G.FS
local args = arg or {...}

-- -- Parse options -- --
local nLines = 10
local files = {}

local i = 1
while i <= #args do
    local a = args[i]
    if a == "--help" or a == "-h" then
        print("Usage: tail [OPTIONS] [FILE...]")
        print("  -n N   print last N lines (default 10)")
        return 0
    elseif a == "-n" then
        i = i + 1
        local n = tonumber(args[i])
        if not n then
            io.stderr:write("tail: invalid number of lines: '" .. tostring(args[i]) .. "'\n")
            return 1
        end
        nLines = n
    elseif a:sub(1, 2) == "-n" and #a > 2 then
        local n = tonumber(a:sub(3))
        if not n then
            io.stderr:write("tail: invalid number of lines: '" .. a:sub(3) .. "'\n")
            return 1
        end
        nLines = n
    elseif a:sub(1, 1) == "-" and #a > 1 and a ~= "-" then
        io.stderr:write("tail: invalid option -- '" .. a .. "'\n")
        return 1
    else
        table.insert(files, a)
    end
    i = i + 1
end

if #files == 0 then
    io.stderr:write("tail: no input files\n")
    return 1
end

-- -- Tail each file -- --
local multi = #files > 1
local ret = 0

local function tailOne(file)
    local real = FS and FS.resolve(file) or file
    if not fs.exists(real) then
        io.stderr:write("tail: cannot open '" .. file .. "' for reading: No such file or directory\n")
        return 1
    end
    if fs.isDir(real) then
        io.stderr:write("tail: error reading '" .. file .. "': Is a directory\n")
        return 1
    end
    local f = FS and FS.open(file, "r") or fs.open(real, "r")
    if not f then
        io.stderr:write("tail: cannot open '" .. file .. "'\n")
        return 1
    end
    local content = f.readAll()
    f.close()

    -- Read all lines into a table
    local lines = {}
    for line in (content or ""):gmatch("([^\n]*)") do
        table.insert(lines, line)
    end
    -- Strip a single trailing empty token from files ending with newline
    if #lines > 0 and lines[#lines] == "" and (content or ""):sub(-1) == "\n" then
        table.remove(lines)
    end

    -- Print last nLines
    local start = math.max(1, #lines - nLines + 1)
    for j = start, #lines do
        print(lines[j])
    end
    return 0
end

for idx, file in ipairs(files) do
    if multi then
        if idx > 1 then print() end
        print("==> " .. file .. " <==")
    end
    local r = tailOne(file)
    if r ~= 0 then ret = r end
end

return ret
