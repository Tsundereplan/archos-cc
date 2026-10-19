-- bin/grep.lua  —  Search for patterns in files
-- Usage: grep [OPTIONS] PATTERN [FILE...]
-- Options:
--   -i   case-insensitive match
--   -n   prefix each match with its line number
--   -v   invert match (print non-matching lines)
--   -r   recurse into subdirectories
--   -c   print only a count of matching lines per file
-- Exit codes: 0 = matches found, 1 = no matches, 2 = error

local FS = _G.FS
local args = arg or {...}

-- -- Option parsing -- --
local opts = {
    ignoreCase = false,
    lineNum    = false,
    invert     = false,
    recurse    = false,
    countOnly  = false,
}
local positional = {}

local i = 1
while i <= #args do
    local a = args[i]
    if a == "--help" or a == "-h" then
        print("Usage: grep [OPTIONS] PATTERN [FILE...]")
        print("  -i   case-insensitive")
        print("  -n   line numbers")
        print("  -v   invert match")
        print("  -r   recurse into subdirectories")
        print("  -c   count matching lines only")
        return 0
    elseif a:sub(1, 1) == "-" and #a > 1 and a ~= "-" then
        -- Walk chars of a short-flag cluster like -in
        for j = 2, #a do
            local c = a:sub(j, j)
            if c == "i" then opts.ignoreCase = true
            elseif c == "n" then opts.lineNum = true
            elseif c == "v" then opts.invert = true
            elseif c == "r" then opts.recurse = true
            elseif c == "c" then opts.countOnly = true
            else
                io.stderr:write("grep: invalid option -- '" .. c .. "'\n")
                return 2
            end
        end
    else
        table.insert(positional, a)
    end
    i = i + 1
end

if #positional == 0 then
    io.stderr:write("grep: no pattern specified\n")
    return 2
end

local pattern = table.remove(positional, 1)
local files = positional

-- -- Build the matcher -- --
local pat
if opts.ignoreCase then
    -- Lowercase both sides; pattern uses lowercased chars
    pat = pattern:lower()
else
    pat = pattern
end

local function matches(line)
    local hay = opts.ignoreCase and line:lower() or line
    local found = hay:find(pat) ~= nil
    if opts.invert then return not found end
    return found
end

-- -- File collection (handles -r) -- --
local function isDir(p)
    if FS then return FS.isDir(p) end
    return fs.isDir(p)
end
local function exists(p)
    if FS then return FS.exists(p) end
    return fs.exists(p)
end
local function listDir(p)
    if FS then return FS.list(p) or {} end
    return fs.list(p)
end

local collected = {}  -- list of {path = ..., display = ...}
local function addFile(path, display)
    table.insert(collected, { path = path, display = display or path })
end

local function walk(path, display)
    if not exists(path) then
        io.stderr:write("grep: " .. (display or path) .. ": No such file or directory\n")
        return false
    end
    if isDir(path) then
        if not opts.recurse then
            io.stderr:write("grep: " .. (display or path) .. ": Is a directory\n")
            return false
        end
        local items = listDir(path)
        table.sort(items)
        for _, n in ipairs(items) do
            local child = path
            if child:sub(-1) ~= "/" then child = child .. "/" end
            child = child .. n
            local disp = (display or path) .. "/" .. n
            walk(child, disp)
        end
        return true
    end
    addFile(path, display)
    return true
end

if #files == 0 then
    -- No stdin support in CC:Tweaked headless shell
    io.stderr:write("grep: no input\n")
    return 2
end

local hadError = false
for _, f in ipairs(files) do
    if not walk(f, f) then hadError = true end
end

local multi = #collected > 1
local anyMatch = false
local ret = 1

-- -- Search loop -- --
for _, entry in ipairs(collected) do
    local f = FS and FS.open(entry.path, "r") or fs.open(entry.path, "r")
    if not f then
        io.stderr:write("grep: " .. entry.display .. ": Cannot open file\n")
        hadError = true
        ret = 2
    else
        local content = f.readAll()
        f.close()
        -- Split into a table of lines so we can skip the trailing empty token
        -- that gmatch produces when the file ends in a newline.
        local lines = {}
        for line in (content or ""):gmatch("([^\n]*)") do
            table.insert(lines, line)
        end
        if #lines > 0 and lines[#lines] == ""
           and (content or ""):sub(-1) == "\n" then
            table.remove(lines)
        end
        local count = 0
        for ln, line in ipairs(lines) do
            if matches(line) then
                anyMatch = true
                count = count + 1
                if not opts.countOnly then
                    local prefix = ""
                    if multi then prefix = entry.display .. ":" end
                    if opts.lineNum then
                        prefix = prefix .. string.format("%d:", ln)
                    end
                    print(prefix .. line)
                end
            end
        end
        if opts.countOnly then
            local prefix = multi and (entry.display .. ":") or ""
            print(prefix .. tostring(count))
        end
    end
end

if hadError and not anyMatch then return 2 end
if anyMatch then return 0 end
return 1
