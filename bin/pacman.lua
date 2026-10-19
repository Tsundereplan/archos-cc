-- bin/pacman.lua  —  Arch Linux-style package manager CLI
-- Usage:
--   pacman -Sy                sync databases
--   pacman -Su                upgrade all packages
--   pacman -Syu               sync + upgrade
--   pacman -S <pkg>           install package
--   pacman -R <pkg>           remove package
--   pacman -Q                 list installed packages
--   pacman -Qs <query>        search installed packages
--   pacman -Ss <query>        search available packages
--   pacman -Si <pkg>          info about available package
--   pacman -Qi <pkg>          info about installed package
--   pacman -Sc                clean package cache
--   pacman -V                 print version
--   pacman -h                 print help

local Pacman = _G.Pacman
local args    = {...}

local hasColor = term.isColor and term.isColor()
local function c(col, fn)
    if hasColor then term.setTextColor(col) end
    fn()
    if hasColor then term.setTextColor(colors.white) end
end

local VERSION = "8.0 (ArchOS-CC)"

local function usage()
    print("Usage: pacman <operation> [...]")
    print("operations:")
    print("  pacman {-S --sync}    [options] [target]")
    print("  pacman {-R --remove}  [options] <target>")
    print("  pacman {-Q --query}   [options] [target]")
    print("  pacman {-V --version}")
    print("  pacman {-h --help}")
    print("")
    print("Common options:")
    print("  -S   sync / install       -Sy   refresh DB        -Su   upgrade all")
    print("  -Syu refresh + upgrade    -Ss   search available -Si   info (avail)")
    print("  -R   remove               -Q    list installed    -Qs   search installed")
    print("  -Qi  info (installed)     -Sc   clean cache")
    return 0
end

if not Pacman then
    io.stderr:write("pacman: package manager not available\n")
    return 1
end

-- Make sure local DB is loaded
if Pacman.loadLocalDb then Pacman.loadLocalDb() end
if not Pacman.installed then Pacman.installed = {} end
if not Pacman.available then Pacman.available = {} end

-- Parse combined short flags like -Syu into {S=true, y=true, u=true}
local ops = {}
local positional = {}
for _, a in ipairs(args) do
    if a:sub(1, 1) == "-" and #a > 1 and a:sub(2, 2) ~= "-" then
        for j = 2, #a do
            local ch = a:sub(j, j)
            ops[ch] = true
        end
    elseif a:sub(1, 2) == "--" then
        local name = a:sub(3)
        if     name == "sync"    then ops["S"] = true
        elseif name == "remove"  then ops["R"] = true
        elseif name == "query"   then ops["Q"] = true
        elseif name == "version" then ops["V"] = true
        elseif name == "help"    then ops["h"] = true
        else ops[name] = true end
    else
        table.insert(positional, a)
    end
end

-- Version / help
if ops["V"] or ops["v"] then
    print("Pacman v" .. VERSION)
    return 0
end
if ops["h"] or ops["help"] then
    return usage()
end

-- Convert a size in bytes to a human string
local function humanSize(n)
    if not n then return "?" end
    if n < 1024 then return tostring(n) .. " B" end
    if n < 1024 * 1024 then return string.format("%.1f KiB", n / 1024) end
    return string.format("%.1f MiB", n / (1024 * 1024))
end

-- Yes/No prompt
local function promptYN(question)
    io.write(question .. " [Y/n] ")
    local line = read()
    if not line then return false end
    line = line:lower():gsub("^%s+", ""):gsub("%s+$", "")
    if line == "" or line:sub(1, 1) == "y" then return true end
    return false
end

-- -- Query: list installed (-Q)
local function doListInstalled()
    local list = Pacman.listInstalled and Pacman.listInstalled() or {}
    if #list == 0 then
        c(colors.yellow, function() print("no packages installed") end)
        return 0
    end
    for _, pkg in ipairs(list) do
        c(colors.green, function()
            print(string.format("  %s %s", pkg.name, pkg.version or "?"))
        end)
    end
    return 0
end

-- -- Query: search installed (-Qs)
local function doSearchInstalled(query)
    if not query then
        io.stderr:write("pacman -Qs: missing query\n")
        return 1
    end
    local list = Pacman.listInstalled and Pacman.listInstalled() or {}
    local found = false
    for _, pkg in ipairs(list) do
        local matches = pkg.name:find(query, 1, true)
            or (pkg.description and pkg.description:find(query, 1, true))
        if matches then
            found = true
            c(colors.green, function()
                io.write(string.format("%s/%s %s",
                    pkg.repo or "local", pkg.name, pkg.version or "?"))
            end)
            if pkg.description and pkg.description ~= "" then
                c(colors.white, function()
                    print("  " .. pkg.description)
                end)
            else
                print("")
            end
        end
    end
    if not found then
        c(colors.yellow, function() print("no matching packages found") end)
    end
    return 0
end

-- -- Sync: search available (-Ss)
local function doSearchAvailable(query)
    if not query then
        io.stderr:write("pacman -Ss: missing query\n")
        return 1
    end
    if not _G.Network or not _G.Network.online then
        c(colors.yellow, function()
            io.stderr:write("pacman: warning: network is offline; using cached DB\n")
        end)
    end
    local results
    if Pacman.search then
        results = Pacman.search(query)
    else
        results = {}
        for name, pkg in pairs(Pacman.available) do
            if name:find(query, 1, true) then table.insert(results, pkg) end
        end
    end
    if #results == 0 then
        c(colors.yellow, function() print("no matching packages found") end)
        return 1
    end
    for _, pkg in ipairs(results) do
        c(colors.green, function()
            io.write(string.format("%s/%s %s",
                pkg.repo or "core", pkg.name, pkg.version or "?"))
        end)
        if pkg.description and pkg.description ~= "" then
            c(colors.white, function()
                print("  " .. pkg.description)
            end)
        else
            print("")
        end
    end
    return 0
end

-- -- Sync: info about available package (-Si)
local function doInfoAvailable(name)
    if not name then
        io.stderr:write("pacman -Si: missing package name\n")
        return 1
    end
    local info
    if Pacman.info then info = Pacman.info(name) end
    local pkg = (info and info.available) or Pacman.available[name]
    if not pkg then
        c(colors.red, function() io.stderr:write("pacman: package '" .. name .. "' was not found\n") end)
        return 1
    end
    c(colors.cyan, function() print(string.format("Repository      : %s", pkg.repo or "core")) end)
    c(colors.cyan, function() print(string.format("Name            : %s", pkg.name)) end)
    c(colors.cyan, function() print(string.format("Version         : %s", pkg.version or "?")) end)
    if pkg.description then
        c(colors.cyan, function() print(string.format("Description     : %s", pkg.description)) end)
    end
    if pkg.url then
        c(colors.cyan, function() print(string.format("URL             : %s", pkg.url)) end)
    end
    if pkg.depends and #pkg.depends > 0 then
        c(colors.cyan, function() print(string.format("Depends On      : %s", table.concat(pkg.depends, "  "))) end)
    end
    if pkg.url then
        local size = pkg.url and #pkg.url or 0
        c(colors.cyan, function() print(string.format("Download Size   : %s", humanSize(size))) end)
    end
    return 0
end

-- -- Query: info about installed package (-Qi)
local function doInfoInstalled(name)
    if not name then
        io.stderr:write("pacman -Qi: missing package name\n")
        return 1
    end
    local info
    if Pacman.info then info = Pacman.info(name) end
    local pkg = (info and info.installed) or Pacman.installed[name]
    if not pkg then
        c(colors.red, function() io.stderr:write("pacman: package '" .. name .. "' was not found\n") end)
        return 1
    end
    c(colors.green, function() print(string.format("Name            : %s", pkg.name)) end)
    c(colors.green, function() print(string.format("Version         : %s", pkg.version or "?")) end)
    if pkg.description then
        c(colors.green, function() print(string.format("Description     : %s", pkg.description)) end)
    end
    c(colors.green, function() print(string.format("Repository      : %s", pkg.repo or "local")) end)
    if pkg.installDate then
        c(colors.green, function() print(string.format("Install Date    : %s", tostring(pkg.installDate))) end)
    end
    if pkg.files and #pkg.files > 0 then
        c(colors.green, function()
            print(string.format("Installed Size  : %d files", #pkg.files))
        end)
    end
    return 0
end

-- -- Sync databases (-Sy)
local function doSyncDb()
    if not _G.Network or not _G.Network.online then
        c(colors.red, function() io.stderr:write("pacman: network is offline\n") end)
        return 1
    end
    c(colors.cyan, function() print(":: Synchronizing package databases ...") end)
    local ok, err = Pacman.sync()
    if ok then
        c(colors.green, function() print(":: Databases synchronized.") end)
        return 0
    end
    c(colors.red, function() io.stderr:write("pacman: sync failed: " .. tostring(err or "?") .. "\n") end)
    return 1
end

-- -- Upgrade all (-Su)
local function doUpgrade()
    c(colors.cyan, function() print(":: Starting full system upgrade ...") end)
    local count = Pacman.upgrade and Pacman.upgrade() or 0
    if count == 0 then
        c(colors.green, function() print(":: There is nothing to do.") end)
    else
        c(colors.green, function() print(string.format(":: %d package(s) upgraded.", count)) end)
    end
    return 0
end

-- -- Install a package (-S <pkg>)
local function doInstall(name)
    if not name then
        io.stderr:write("pacman -S: missing package name\n")
        return 1
    end
    local info = Pacman.info and Pacman.info(name) or {}
    local pkg = info.available or Pacman.available[name]
    if not pkg then
        c(colors.red, function()
            io.stderr:write("pacman: target not found: " .. name .. "\n")
        end)
        return 1
    end

    -- Resolve dependencies (just for show)
    c(colors.cyan, function() print(":: Resolving dependencies ...") end)
    c(colors.cyan, function() print(":: Calculating download size ...") end)

    local targets = { pkg }
    if pkg.depends then
        for _, dep in ipairs(pkg.depends) do
            if not Pacman.installed[dep] and Pacman.available[dep] then
                table.insert(targets, Pacman.available[dep])
            end
        end
    end

    local totalSize = 0
    for _, t in ipairs(targets) do
        totalSize = totalSize + (t.url and #t.url or 0)
    end

    c(colors.yellow, function()
        print(string.format(":: Total Download Size: %s", humanSize(totalSize)))
    end)
    c(colors.yellow, function()
        print(string.format(":: Total Installed Size: %s", humanSize(totalSize)))
    end)
    print("")

    -- Confirmation
    local targetList = ""
    for i, t in ipairs(targets) do
        targetList = targetList .. t.name .. (i < #targets and " " or "")
    end
    if not promptYN(":: Proceed with installation? (" .. #targets .. " package(s))") then
        c(colors.yellow, function() print(":: Installation cancelled.") end)
        return 0
    end

    -- Install each target
    for _, t in ipairs(targets) do
        c(colors.cyan, function() print(string.format(":: Installing %s ...", t.name)) end)
        local ok, err = Pacman.install(t.name)
        if ok then
            c(colors.green, function() print(string.format(":: %s installed.", t.name)) end)
        else
            c(colors.red, function()
                io.stderr:write("pacman: install failed for " .. t.name .. ": " .. tostring(err or "?") .. "\n")
            end)
            return 1
        end
    end
    return 0
end

-- -- Remove a package (-R <pkg>)
local function doRemove(name)
    if not name then
        io.stderr:write("pacman -R: missing package name\n")
        return 1
    end
    if not Pacman.installed[name] then
        c(colors.red, function()
            io.stderr:write("pacman: target not installed: " .. name .. "\n")
        end)
        return 1
    end
    if not promptYN(":: Do you want to remove " .. name .. "?") then
        c(colors.yellow, function() print(":: Removal cancelled.") end)
        return 0
    end
    local ok, err = Pacman.remove(name)
    if ok then
        c(colors.green, function() print(string.format(":: %s removed.", name)) end)
        return 0
    end
    c(colors.red, function()
        io.stderr:write("pacman: remove failed: " .. tostring(err or "?") .. "\n")
    end)
    return 1
end

-- -- Clean cache (-Sc)
local function doCleanCache()
    local cacheDir = (Pacman.config and Pacman.config.cacheDir) or "/var/cache/pacman/pkg"
    local exists
    if _G.FS then exists = _G.FS.exists(cacheDir) else exists = fs.exists(cacheDir) end
    if not exists then
        c(colors.yellow, function() print(":: Cache directory does not exist.") end)
        return 0
    end
    if not promptYN(":: Do you want to remove all packages from cache?") then
        c(colors.yellow, function() print(":: Clean cancelled.") end)
        return 0
    end
    local list
    if _G.FS then list = _G.FS.list(cacheDir) else list = fs.list(cacheDir) end
    local count = 0
    for _, f in ipairs(list or {}) do
        local path = cacheDir .. "/" .. f
        if _G.FS then _G.FS.delete(path) else fs.delete(path) end
        count = count + 1
    end
    c(colors.green, function() print(string.format(":: Removed %d cached package(s).", count)) end)
    return 0
end

-- Dispatch
-- Combined -Sy / -Su / -Syu
if ops["S"] and ops["y"] and ops["u"] then
    local r1 = doSyncDb()
    if r1 ~= 0 then return r1 end
    return doUpgrade()
elseif ops["S"] and ops["y"] then
    return doSyncDb()
elseif ops["S"] and ops["u"] then
    return doUpgrade()
elseif ops["S"] and ops["s"] then
    return doSearchAvailable(positional[1])
elseif ops["S"] and ops["i"] then
    return doInfoAvailable(positional[1])
elseif ops["S"] then
    if positional[1] == nil then
        -- `pacman -S` alone is invalid
        io.stderr:write("pacman: -S requires a target package or option\n")
        usage()
        return 1
    end
    return doInstall(positional[1])
elseif ops["R"] then
    return doRemove(positional[1])
elseif ops["Q"] and ops["s"] then
    return doSearchInstalled(positional[1])
elseif ops["Q"] and ops["i"] then
    return doInfoInstalled(positional[1])
elseif ops["Q"] then
    return doListInstalled()
elseif ops["S"] == nil and ops["R"] == nil and ops["Q"] == nil then
    -- No recognized operation
    usage()
    return 1
end

return 0
