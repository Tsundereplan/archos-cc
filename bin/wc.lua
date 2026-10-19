-- bin/wc.lua  —  Count lines, words, and characters in files
-- Usage: wc [OPTIONS] [FILE...]
-- Options:
--   -l   lines
--   -w   words
--   -c   characters (bytes)
-- Default: print lines, words, and chars for each file (and a total if >1 file)

local FS = _G.FS
local args = arg or {...}

-- -- Option parsing -- --
local opts = { l = false, w = false, c = false }
local files = {}

local i = 1
while i <= #args do
    local a = args[i]
    if a == "--help" or a == "-h" then
        print("Usage: wc [OPTIONS] [FILE...]")
        print("  -l   lines")
        print("  -w   words")
        print("  -c   characters")
        return 0
    elseif a:sub(1, 1) == "-" and #a > 1 and a ~= "-" then
        for j = 2, #a do
            local c = a:sub(j, j)
            if c == "l" then opts.l = true
            elseif c == "w" then opts.w = true
            elseif c == "c" then opts.c = true
            else
                io.stderr:write("wc: invalid option -- '" .. c .. "'\n")
                return 1
            end
        end
    else
        table.insert(files, a)
    end
    i = i + 1
end

-- If no flags chosen, default to all three (l, w, c)
local anyFlag = opts.l or opts.w or opts.c
if not anyFlag then
    opts.l, opts.w, opts.c = true, true, true
end

if #files == 0 then
    io.stderr:write("wc: no input files\n")
    return 1
end

-- -- Counting -- --
local function count(content)
    local lines = 0
    local words = 0
    local chars = 0
    if content == nil then content = "" end
    chars = #content
    -- Lines: count of \n; if last char is not \n, add 1 (matches coreutils on text files)
    local nl = 0
    for _ in content:gmatch("\n") do nl = nl + 1 end
    if content ~= "" and content:sub(-1) ~= "\n" then
        lines = nl + 1
    else
        lines = nl
    end
    -- Words: maximal runs of non-whitespace
    for _ in content:gmatch("%S+") do words = words + 1 end
    return lines, words, chars
end

-- -- Format one line -- --
local function formatLine(lines, words, chars, filename)
    local parts = {}
    if opts.l then table.insert(parts, string.format("%8d", lines)) end
    if opts.w then table.insert(parts, string.format("%8d", words)) end
    if opts.c then table.insert(parts, string.format("%8d", chars)) end
    local line = table.concat(parts, " ")
    if filename then line = line .. " " .. filename end
    return line
end

-- -- Iterate -- --
local totals = { l = 0, w = 0, c = 0 }
local ret = 0
local okCount = 0
local multi = #files > 1

for _, file in ipairs(files) do
    local real = FS and FS.resolve(file) or file
    if not fs.exists(real) then
        io.stderr:write("wc: " .. file .. ": No such file or directory\n")
        ret = 1
    elseif fs.isDir(real) then
        io.stderr:write("wc: " .. file .. ": Is a directory\n")
        ret = 1
    else
        local f = FS and FS.open(file, "r") or fs.open(real, "r")
        if not f then
            io.stderr:write("wc: " .. file .. ": Cannot open file\n")
            ret = 1
        else
            local content = f.readAll()
            f.close()
            local l, w, c = count(content)
            totals.l = totals.l + l
            totals.w = totals.w + w
            totals.c = totals.c + c
            print(formatLine(l, w, c, file))
            okCount = okCount + 1
        end
    end
end

-- -- Totals -- --
if multi and okCount > 1 then
    print(formatLine(totals.l, totals.w, totals.c, "total"))
end

return ret
