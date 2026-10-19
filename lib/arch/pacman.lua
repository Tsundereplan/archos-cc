--[[
    lib/arch/pacman.lua  —  Pacman-style package manager
    ===================================================
    Manages software packages from:
      * Official ArchOS-CC repository (GitHub-hosted index)
      * pinestore.cc (community app store)
      * AUR-like: arbitrary GitHub repos
      * Local /var/cache/pacman/pkg/

    Package metadata stored in /var/lib/pacman/local/<name>-<ver>/
      - desc      (description, dependencies, etc.)
      - files     (list of installed files)
      - install   (optional install script)

    Sync DB at /var/lib/pacman/sync/
      - core.db, extra.db, community.db, aur.db
]]

local Pacman = {}

Pacman.config = {
    repos = {
        { name = "core",      url = "https://raw.githubusercontent.com/YOUR_USER/archos-cc-repo/main/core.db" },
        { name = "extra",    url = "https://raw.githubusercontent.com/YOUR_USER/archos-cc-repo/main/extra.db" },
        { name = "aur",       url = "https://raw.githubusercontent.com/YOUR_USER/archos-cc-aur/main/" },
        { name = "pinestore", url = "https://pinestore.cc/api/" },
    },
    cacheDir    = "/var/cache/pacman/pkg",
    localDbDir  = "/var/lib/pacman/local",
    syncDbDir   = "/var/lib/pacman/sync",
    rootDir     = "/",
    arch        = "any",  -- CC:Tweaked has no arch
}

-- Installed packages: name -> { name, version, description, files, installDate }
Pacman.installed = {}
Pacman.available = {}    -- name -> { name, version, description, repo, url, depends }

local function ensureDirs()
    for _, d in ipairs({Pacman.config.cacheDir, Pacman.config.localDbDir, Pacman.config.syncDbDir}) do
        if not fs.exists(d) then fs.makeDir(d) end
    end
end

function Pacman.loadLocalDb()
    Pacman.installed = {}
    ensureDirs()
    if not fs.exists(Pacman.config.localDbDir) then return end
    for _, name in ipairs(fs.list(Pacman.config.localDbDir)) do
        local pkgDir = Pacman.config.localDbDir .. "/" .. name
        if fs.isDir(pkgDir) then
            local descFile = pkgDir .. "/desc"
            if fs.exists(descFile) then
                local f = fs.open(descFile, "r")
                if f then
                    local content = f.readAll()
                    f.close()
                    local pkg = { name = name, files = {} }
                    for line in content:gmatch("[^\n]+") do
                        local k, v = line:match("^([^=]+)=(.*)$")
                        if k and v then
                            local key = k
                            pkg[key] = v
                        end
                    end
                    -- Load files list
                    local filesFile = pkgDir .. "/files"
                    if fs.exists(filesFile) then
                        local ff = fs.open(filesFile, "r")
                        if ff then
                            for line in ff.readLine do
                                if line and line ~= "" then
                                    table.insert(pkg.files, line)
                                end
                            end
                            ff.close()
                        end
                    end
                    Pacman.installed[pkg.name or name] = pkg
                end
            end
        end
    end
end

function Pacman.saveLocalPkg(pkg)
    local pkgDir = Pacman.config.localDbDir .. "/" .. pkg.name
    if not fs.exists(pkgDir) then fs.makeDir(pkgDir) end
    local f = fs.open(pkgDir .. "/desc", "w")
    if f then
        f.write("name=" .. pkg.name .. "\n")
        f.write("version=" .. pkg.version .. "\n")
        f.write("description=" .. pkg.description .. "\n")
        f.write("repo=" .. (pkg.repo or "local") .. "\n")
        f.write("installDate=" .. tostring(os.time()) .. "\n")
        f.close()
    end
    local ff = fs.open(pkgDir .. "/files", "w")
    if ff then
        for _, file in ipairs(pkg.files or {}) do
            ff.write(file .. "\n")
        end
        ff.close()
    end
end

-- Sync: refresh package lists from repos
function Pacman.sync()
    ensureDirs()
    Pacman.available = {}
    if not _G.Network or not _G.Network.online then
        return false, "network offline"
    end
    for _, repo in ipairs(Pacman.config.repos) do
        if repo.url and repo.url:sub(1, 4) == "http" then
            local body = _G.Network.httpGet(repo.url)
            if body then
                -- Parse simple line-based package list:
                -- name|version|description|url|depends
                for line in body:gmatch("[^\n]+") do
                    local name, ver, desc, url, deps = line:match("^([^|]+)|([^|]+)|([^|]*)|([^|]*)|(.*)$")
                    if name then
                        Pacman.available[name] = {
                            name = name,
                            version = ver,
                            description = desc,
                            url = url,
                            depends = deps and deps:split(",") or {},
                            repo = repo.name,
                        }
                    end
                end
            end
        end
    end
    return true
end

-- string.split helper
local function splitString(s, sep)
    if not s or s == "" then return {} end
    local out = {}
    for part in s:gmatch("[^" .. sep .. "]+") do
        table.insert(out, part)
    end
    return out
end

-- Install a package by name
function Pacman.install(name)
    if not Pacman.available[name] then
        return false, "package not found: " .. name
    end
    local pkg = Pacman.available[name]
    -- Check dependencies
    for _, dep in ipairs(pkg.depends or {}) do
        if not Pacman.installed[dep] then
            -- Try recursive install
            local ok, err = Pacman.install(dep)
            if not ok then
                return false, "dependency install failed: " .. dep .. " (" .. err .. ")"
            end
        end
    end

    -- Download the package (Lua script) and execute its installer
    if not pkg.url then
        return false, "package has no download URL"
    end
    local body = _G.Network.httpGet(pkg.url)
    if not body then
        return false, "download failed"
    end
    -- Cache the package
    local cachePath = Pacman.config.cacheDir .. "/" .. name .. "-" .. pkg.version .. ".lua"
    local f = fs.open(cachePath, "w")
    if f then
        f.write(body)
        f.close()
    end
    -- Execute the installer (it should return a table with install() and files)
    local fn, err = load(body, cachePath, "t", _G)
    if not fn then return false, "load error: " .. err end
    local ok, result = pcall(fn)
    if not ok then return false, "install error: " .. result end

    local installedFiles = {}
    if type(result) == "table" then
        if result.install then
            local iok, ierr = pcall(result.install, name, pkg)
            if not iok then return false, "install script failed: " .. ierr end
        end
        if result.files then installedFiles = result.files end
    end
    -- Register in local DB
    local record = {
        name = name,
        version = pkg.version,
        description = pkg.description,
        repo = pkg.repo,
        files = installedFiles,
    }
    Pacman.installed[name] = record
    Pacman.saveLocalPkg(record)
    -- Dispatch event
    if _G.Events then
        _G.Events.dispatch(_G.Events.TYPES.PACKAGE_INSTALL, name, pkg.version)
    end
    return true
end

-- Remove a package
function Pacman.remove(name)
    local pkg = Pacman.installed[name]
    if not pkg then return false, "package not installed" end
    -- Remove all installed files
    for _, file in ipairs(pkg.files or {}) do
        if fs.exists(file) then
            fs.delete(file)
        end
    end
    -- Run uninstall hook if present
    local pkgDir = Pacman.config.localDbDir .. "/" .. name
    if fs.exists(pkgDir .. "/install") then
        local f = fs.open(pkgDir .. "/install", "r")
        if f then
            local script = f.readAll()
            f.close()
            local fn = load(script, "uninstall", "t", _G)
            if fn then pcall(fn, "remove", name) end
        end
    end
    -- Remove from local DB
    fs.delete(pkgDir)
    Pacman.installed[name] = nil
    if _G.Events then
        _G.Events.dispatch(_G.Events.TYPES.PACKAGE_REMOVE, name)
    end
    return true
end

-- Upgrade all installed packages
function Pacman.upgrade()
    local upgraded = 0
    for name, pkg in pairs(Pacman.installed) do
        local avail = Pacman.available[name]
        if avail and avail.version ~= pkg.version then
            local ok = Pacman.install(name)
            if ok then upgraded = upgraded + 1 end
        end
    end
    return upgraded
end

-- Search available packages
function Pacman.search(query)
    local results = {}
    for name, pkg in pairs(Pacman.available) do
        if name:find(query, 1, true) or (pkg.description and pkg.description:find(query, 1, true)) then
            table.insert(results, pkg)
        end
    end
    table.sort(results, function(a, b) return a.name < b.name end)
    return results
end

-- Show package info
function Pacman.info(name)
    local installed = Pacman.installed[name]
    local available = Pacman.available[name]
    return {
        installed = installed,
        available = available,
    }
end

-- List installed packages
function Pacman.listInstalled()
    local out = {}
    for name, pkg in pairs(Pacman.installed) do
        table.insert(out, pkg)
    end
    table.sort(out, function(a, b) return a.name < b.name end)
    return out
end

function Pacman.init()
    Pacman.loadLocalDb()
end

return Pacman
