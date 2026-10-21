--[[
    bin/cleanup.lua  —  Free disk space by removing unnecessary files
    ===================================================================
    Removes:
      - /backup/* (old system backups)
      - /startup.lua.bak (old startup backup)
      - /installer.lua (already installed, not needed)
      - /var/cache/pacman/* (package cache)
      - /tmp/* (temporary files)
      - .gitkeep files (only needed in git, not in production)
      - /var/log/*.log (old log files, except current boot.log)

    Usage:  cleanup          # show what would be deleted
            cleanup --force  # actually delete
]]

local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end

local args = arg or {...}
local force = false
for _, a in ipairs(args) do
    if a == "--force" or a == "-f" then force = true end
end

setColor(colors.cyan)
print("ArchOS-CC Cleanup")
print("==================")
print("")
setColor(colors.white)

local function getDirSize(path)
    if not fs.exists(path) then return 0 end
    if not fs.isDir(path) then return fs.getSize(path) end
    local total = 0
    for _, name in ipairs(fs.list(path)) do
        total = total + getDirSize(path .. "/" .. name)
    end
    return total
end

local function humanSize(b)
    if b < 1024 then return b .. " B"
    elseif b < 1024 * 1024 then return string.format("%.1f KB", b / 1024)
    else return string.format("%.1f MB", b / (1024 * 1024)) end
end

-- Files/dirs to clean up
local targets = {
    { path = "/backup",                desc = "Old system backups",     safe = true },
    { path = "/startup.lua.bak",       desc = "Old startup.lua backup", safe = true },
    { path = "/installer.lua",         desc = "Installer script",       safe = true },
    { path = "/var/cache/pacman/pkg",  desc = "Package cache",          safe = true },
    { path = "/tmp/update.pending",    desc = "Stale update pending",   safe = true },
    { path = "/var/log/boot.log.bak",  desc = "Old boot log backup",    safe = true },
}

-- Find .gitkeep files
local gitkeepFiles = {}
local function scanForGitkeep(path)
    if not fs.exists(path) then return end
    if fs.isDir(path) then
        for _, name in ipairs(fs.list(path)) do
            scanForGitkeep(path .. "/" .. name)
        end
    else
        if path:match("%.gitkeep$") or path:match("%.keep$") then
            table.insert(gitkeepFiles, path)
        end
    end
end
scanForGitkeep("/")

setColor(colors.yellow)
print("Files to clean:")
setColor(colors.white)
local totalSize = 0
for _, t in ipairs(targets) do
    if fs.exists(t.path) then
        local size = getDirSize(t.path)
        totalSize = totalSize + size
        print(string.format("  %-30s %10s  %s", t.path, humanSize(size), t.desc))
    end
end

-- Show gitkeep files
local gitkeepSize = 0
for _, path in ipairs(gitkeepFiles) do
    gitkeepSize = gitkeepSize + (fs.getSize(path) or 0)
end
if #gitkeepFiles > 0 then
    print(string.format("  %-30s %10s  %s", "(" .. #gitkeepFiles .. " .gitkeep files)", humanSize(gitkeepSize), "Marker files (only for git)"))
    totalSize = totalSize + gitkeepSize
end

print("")
setColor(colors.green)
print(string.format("Total space to free: %s", humanSize(totalSize)))
setColor(colors.white)
print("Current free space: " .. humanSize(fs.getFreeSpace("/")))
print("")

if not force then
    setColor(colors.yellow)
    print("This is a DRY RUN. To actually delete, run:")
    print("  cleanup --force")
    setColor(colors.white)
    return 0
end

-- Actually delete
setColor(colors.cyan)
print("Deleting ...")
setColor(colors.white)
local freed = 0
for _, t in ipairs(targets) do
    if fs.exists(t.path) then
        local size = getDirSize(t.path)
        local ok = pcall(fs.delete, t.path)
        if ok then
            freed = freed + size
            setColor(colors.green)
            print("  [OK] " .. t.path .. " (" .. humanSize(size) .. ")")
            setColor(colors.white)
        else
            setColor(colors.red)
            print("  [FAIL] " .. t.path)
            setColor(colors.white)
        end
    end
end
-- Delete .gitkeep files
for _, path in ipairs(gitkeepFiles) do
    local size = fs.getSize(path) or 0
    local ok = pcall(fs.delete, path)
    if ok then
        freed = freed + size
    end
end

print("")
setColor(colors.green)
print(string.format("Freed: %s", humanSize(freed)))
print("Free space now: " .. humanSize(fs.getFreeSpace("/")))
setColor(colors.white)
return 0
