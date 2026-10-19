-- bin/head.lua  —  Print the first lines of files
-- Usage: head [OPTIONS] [FILE...]
-- Options:
--   -n N   number of lines to print (default 10)
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
        print("Usage: head [OPTIONS] [FILE...]")
        print("  -n N   print first N lines (default 10)")
        return 0
    elseif a == "-n" then
        i = i + 1
        local n = tonumber(args[i])
        if not n then
            io.stderr:write("head: invalid number of lines: '" .. tostring(args[i]) .. "'\n")
            return 1
        end
        nLines = n
    elseif a:sub(1, 2) == "-n" and #a > 2 then
        -- -n5 style
        local n = tonumber(a:sub(3))
        if not n then
            io.stderr:write("head: invalid number of lines: '" .. a:sub(3) .. "'\n")
            return 1
        end
        nLines = n
    elseif a:sub(1, 1) == "-" and #a > 1 and a ~= "-" then
        io.stderr:write("head: invalid option -- '" .. a .. "'\n")
        return 1
    else
        table.insert(files, a)
    end
    i = i + 1
end

if #files == 0 then
    -- No stdin support; bail
    io.stderr:write("head: no input files\n")
    return 1
end

-- -- Print head of each file -- --
local multi = #files > 1
local ret = 0

local function headOne(file)
    local real = FS and FS.resolve(file) or file
    if not fs.exists(real) then
        io.stderr:write("head: cannot open '" .. file .. "' for reading: No such file or directory\n")
        return 1
    end
    if fs.isDir(real) then
        io.stderr:write("head: error reading '" .. file .. "': Is a directory\n")
        return 1
    end
    local f = FS and FS.open(file, "r") or fs.open(real, "r")
    if not f then
        io.stderr:write("head: cannot open '" .. file .. "'\n")
        return 1
    end
    local content = f.readAll()
    f.close()
    local printed = 0
    for line in (content or ""):gmatch("([^\n]*)") do
        if printed >= nLines then break end
        -- Skip the trailing empty token that gmatch produces for files ending in \n
        if line == "" and printed == 0 and (content or "") == "" then
            -- empty file
        end
        print(line)
        printed = printed + 1
    end
    return 0
end

for idx, file in ipairs(files) do
    if multi then
        if idx > 1 then print() end
        print("==> " .. file .. " <==")
    end
    local r = headOne(file)
    if r ~= 0 then ret = r end
end

return ret
