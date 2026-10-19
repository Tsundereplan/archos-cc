-- bin/ls.lua  —  List directory contents
local FS = _G.FS or (fs.exists("/lib/fs.lua") and dofile("/lib/fs.lua"))
local Users = _G.Users
local Permissions = _G.Permissions

local function showHelp()
    print("Usage: ls [OPTION]... [FILE]...")
    print("List information about the FILEs (the current directory by default).")
    print("Sort entries alphabetically.")
    print("")
    print("  -a, --all           show hidden files (starting with .)")
    print("  -l, --long          long format (perms, owner, size, modified)")
    print("  -h, --human         human-readable sizes (K, M)")
    print("  -R, --recursive     list subdirectories recursively")
    print("  -1                   one file per line")
    print("  --help              show this help")
end

local args = {...}
local opts = { all = false, long = false, human = false, recursive = false, oneLine = false }
local targets = {}

for i, a in ipairs(args) do
    if a == "-a" or a == "--all" then opts.all = true
    elseif a == "-l" or a == "--long" then opts.long = true
    elseif a == "-h" or a == "--human" then opts.human = true
    elseif a == "-R" or a == "--recursive" then opts.recursive = true
    elseif a == "-1" then opts.oneLine = true
    elseif a == "-la" or a == "-al" then opts.all = true; opts.long = true
    elseif a == "--help" then showHelp(); return 0
    elseif a:sub(1, 1) == "-" and #a > 1 then
        -- combined short opts like -la
        for j = 2, #a do
            local c = a:sub(j, j)
            if c == "a" then opts.all = true
            elseif c == "l" then opts.long = true
            elseif c == "h" then opts.human = true
            elseif c == "R" then opts.recursive = true
            elseif c == "1" then opts.oneLine = true end
        end
    else
        table.insert(targets, a)
    end
end

if #targets == 0 then table.insert(targets, ".") end

local function humanSize(bytes)
    if not bytes then return "?" end
    if bytes < 1024 then return tostring(bytes) .. "B"
    elseif bytes < 1024 * 1024 then return string.format("%.1fK", bytes / 1024)
    else return string.format("%.1fM", bytes / (1024 * 1024)) end
end

local function modeString(path, isDir)
    if isDir then return "drwxr-xr-x" end
    -- Try to detect executable (ends with .lua)
    if path:sub(-4) == ".lua" then return "-rwxr-xr-x" end
    return "-rw-r--r--"
end

local function listOne(target)
    local real = FS and FS.resolve(target) or target
    if not fs.exists(real) then
        io.stderr:write("ls: cannot access '" .. target .. "': No such file or directory\n")
        return 1
    end
    if not fs.isDir(real) then
        -- single file
        if opts.long then
            local size = fs.getSize(real)
            if opts.human then size = humanSize(size) end
            print(string.format("%s  1 root root %8s %s", modeString(target, false), tostring(size), fs.getName(target)))
        else
            print(fs.getName(target))
        end
        return 0
    end

    if #targets > 1 or opts.recursive then
        print(target .. ":")
    end
    local items = fs.list(real)
    table.sort(items)
    if not opts.all then
        local filtered = {}
        for _, n in ipairs(items) do
            if n:sub(1, 1) ~= "." then table.insert(filtered, n) end
        end
        items = filtered
    end

    if opts.long then
        for _, name in ipairs(items) do
            local child = real
            if child:sub(-1) ~= "/" then child = child .. "/" end
            child = child .. name
            local isDir = fs.isDir(child)
            local size = fs.getSize(child)
            if opts.human then size = humanSize(size) end
            local display = name
            if isDir then
                if term.isColor() then term.setTextColor(colors.lightBlue) end
                display = display .. "/"
            elseif name:sub(-4) == ".lua" then
                if term.isColor() then term.setTextColor(colors.green) end
            end
            print(string.format("%s  1 root root %8s %s", modeString(name, isDir), tostring(size), display))
            if term.isColor() then term.setTextColor(colors.white) end
        end
    elseif opts.oneLine then
        for _, name in ipairs(items) do
            local isDir = fs.isDir((real:sub(-1) == "/" and real or real .. "/") .. name)
            if isDir and term.isColor() then term.setTextColor(colors.lightBlue) end
            print(name)
            if term.isColor() then term.setTextColor(colors.white) end
        end
    else
        -- column layout (simple)
        local line = ""
        for i, name in ipairs(items) do
            local isDir = fs.isDir((real:sub(-1) == "/" and real or real .. "/") .. name)
            if term.isColor() and isDir then term.setTextColor(colors.lightBlue) end
            term.write(name .. (isDir and "/" or "") .. "  ")
            if term.isColor() then term.setTextColor(colors.white) end
            if i % 5 == 0 then
                print()
            end
        end
        if #items % 5 ~= 0 then print() end
    end

    if opts.recursive then
        for _, name in ipairs(items) do
            local child = real
            if child:sub(-1) ~= "/" then child = child .. "/" end
            child = child .. name
            if fs.isDir(child) and name:sub(1, 1) ~= "." then
                print("")
                listOne(FS and FS.normalize(target .. "/" .. name) or target .. "/" .. name)
            end
        end
    end
    return 0
end

local ret = 0
for _, t in ipairs(targets) do
    local r = listOne(t)
    if r ~= 0 then ret = r end
end
return ret
