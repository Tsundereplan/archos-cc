-- bin/arch-update.lua  —  ArchOS-CC system updater (pacman -Syu + kernel check)
-- Usage: arch-update

local Pacman = _G.Pacman
local Network = _G.Network
local Events  = _G.Events
local Kernel  = _G.Kernel
local FS      = _G.FS
local args    = {...}

local hasColor = term.isColor and term.isColor()
local function c(col, fn)
    if hasColor then term.setTextColor(col) end
    fn()
    if hasColor then term.setTextColor(colors.white) end
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

-- Read VERSION from /etc/os-release
local function currentKernelVersion()
    local path = "/etc/os-release"
    local exists
    if FS then exists = FS.exists(path) else exists = fs.exists(path) end
    if not exists then return nil end
    local f
    if FS and FS.open then f = FS.open(path, "r") else f = fs.open(path, "r") end
    if not f then return nil end
    local content = f.readAll()
    f.close()
    for line in (content or ""):gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.*)$")
        if k and v then
            v = v:gsub('^"', ""):gsub('"$', "")
            if k == "VERSION" or k == "VERSION_ID" then return v end
        end
    end
    return nil
end

-- Pull latest /etc/os-release from the main repo on GitHub
local GITHUB_USER = "YOUR_USER"
local GITHUB_REPO = "archos-cc"
local GITHUB_BRANCH = "main"

local function fetchLatestKernelVersion()
    if not Network or not Network.fetchGitHubRaw then return nil end
    if not Network.online then return nil end
    local body = Network.fetchGitHubRaw(GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, "etc/os-release")
    if not body then return nil end
    for line in body:gmatch("[^\r\n]+") do
        local k, v = line:match("^%s*([%w_]+)%s*=%s*(.*)$")
        if k and v then
            v = v:gsub('^"', ""):gsub('"$', "")
            if k == "VERSION" or k == "VERSION_ID" then return v end
        end
    end
    return nil
end

-- Main update flow
local function main()
    -- --help
    for _, a in ipairs(args) do
        if a == "-h" or a == "--help" then
            print("Usage: arch-update")
            print("Synchronize package databases and upgrade the system.")
            return 0
        end
    end

    if not Pacman then
        c(colors.red, function() io.stderr:write("[arch-update] pacman subsystem unavailable\n") end)
        return 1
    end

    -- Make sure local DB is loaded
    if Pacman.loadLocalDb then Pacman.loadLocalDb() end
    if not Pacman.installed then Pacman.installed = {} end
    if not Pacman.available then Pacman.available = {} end

    -- 1. Sync databases
    c(colors.cyan, function() print("[arch-update] Synchronizing package databases ...") end)
    if not Network or not Network.online then
        c(colors.yellow, function() io.stderr:write("[arch-update] warning: network is offline; using cached DB\n") end)
    else
        local ok, err = Pacman.sync()
        if not ok then
            c(colors.yellow, function()
                io.stderr:write("[arch-update] warning: sync failed: " .. tostring(err or "?") .. "\n")
            end)
        end
    end

    -- 2. Look for package updates
    c(colors.cyan, function() print("[arch-update] Looking for updates ...") end)
    local updates = {}
    for name, pkg in pairs(Pacman.installed) do
        local avail = Pacman.available[name]
        if avail and avail.version and pkg.version and avail.version ~= pkg.version then
            table.insert(updates, {
                name = name,
                old  = pkg.version,
                new  = avail.version,
            })
        end
    end
    table.sort(updates, function(a, b) return a.name < b.name end)

    -- 3. Check kernel version
    local curKernel = currentKernelVersion()
    local newKernel = fetchLatestKernelVersion()
    local kernelUpdate = nil
    if curKernel and newKernel and curKernel ~= newKernel then
        kernelUpdate = { old = curKernel, new = newKernel }
    end

    -- 4. Report
    if #updates == 0 and not kernelUpdate then
        c(colors.green, function() print("[arch-update] System is up to date.") end)
        return 0
    end

    if #updates > 0 then
        c(colors.yellow, function() print(string.format("[arch-update] %d package(s) can be updated:", #updates)) end)
        for _, u in ipairs(updates) do
            c(colors.lightBlue, function()
                print(string.format("  %-20s %s -> %s", u.name, u.old, u.new))
            end)
        end
    end

    if kernelUpdate then
        c(colors.yellow, function() print("[arch-update] Kernel update available:") end)
        c(colors.lightBlue, function()
            print(string.format("  %-20s %s -> %s", "archos-kernel", kernelUpdate.old, kernelUpdate.new))
        end)
    end

    -- 5. Confirm
    if not promptYN("Proceed with update?") then
        c(colors.yellow, function() print("[arch-update] Update cancelled.") end)
        return 0
    end

    -- 6. Run upgrade
    if #updates > 0 then
        c(colors.cyan, function() print("[arch-update] Upgrading packages ...") end)
        local count = Pacman.upgrade and Pacman.upgrade() or 0
        c(colors.green, function() print(string.format("[arch-update] %d package(s) upgraded.", count)) end)
    end

    -- 7. Kernel note
    if kernelUpdate then
        c(colors.yellow, function()
            print("[arch-update] Kernel update available; please re-run the installer to flash a new kernel.")
        end)
    end
    return 0
end

return main()
