--[[
    bin/restore.lua  —  Restore system from backup
    Usage:
        restore              Interactive (pick from list)
        restore <path>       Restore from specific backup path
        restore --list       List available backups
]]
local function setColor(c)
    if c and term.isColor() then pcall(function() term.setTextColor(c) end) end
end
local args = arg or ({...})

local function findBackups()
    local backups = {}
    if fs.exists("/backup") and fs.isDir("/backup") then
        for _, name in ipairs(fs.list("/backup")) do
            if name:match("^archos") then
                table.insert(backups, {path="/backup/"..name, source="local", name=name})
            end
        end
    end
    for i = 0, 5 do
        local dp = i == 0 and "/disk" or "/disk"..(i+1)
        if fs.exists(dp) and fs.isDir(dp) then
            for _, name in ipairs(fs.list(dp)) do
                if name:match("^archos") then
                    table.insert(backups, {path=dp.."/"..name, source="disk:"..dp, name=name})
                end
            end
            if fs.exists(dp.."/update-backup") then
                table.insert(backups, {path=dp.."/update-backup", source="disk:"..dp, name="update-backup"})
            end
        end
    end
    return backups
end

if args[1] == "--list" then
    local backups = findBackups()
    if #backups == 0 then
        print("No backups found.")
        print("Create backups with: update backup, update backup disk")
        return 0
    end
    print("Available backups:")
    for i, b in ipairs(backups) do
        print(string.format("  %d. %-45s [%s]", i, b.path, b.source))
    end
    return 0
end

if #args == 0 or args[1] == "-h" then
    print("Usage: restore [path|--list]")
    print("  restore          Interactive mode")
    print("  restore <path>   Restore from path")
    print("  restore --list   List backups")
    return 0
end

local backupPath = nil
if args[1] and args[1]:sub(1,1) == "/" then
    backupPath = args[1]
else
    local backups = findBackups()
    if #backups == 0 then
        print("No backups found!")
        return 1
    end
    print("Available backups:")
    for i, b in ipairs(backups) do
        print(string.format("  %d. %-45s [%s]", i, b.path, b.source))
    end
    print("")
    setColor(colors.yellow)
    term.write("Select backup (1-"..#backups.."): ")
    setColor(colors.white)
    local input = read()
    local idx = tonumber(input)
    if not idx or idx < 1 or idx > #backups then
        print("Invalid selection.")
        return 1
    end
    backupPath = backups[idx].path
end

if not fs.exists(backupPath) then
    print("Backup not found: "..backupPath)
    return 1
end

setColor(colors.red)
print("")
print("WARNING: This will OVERWRITE current system files!")
print("Source: "..backupPath)
print("")
setColor(colors.yellow)
term.write("Type 'yes' to confirm: ")
setColor(colors.white)
local confirm = read()
if confirm:lower() ~= "yes" then
    print("Cancelled.")
    return 0
end

setColor(colors.cyan)
print("Restoring from "..backupPath.." ...")
setColor(colors.white)

local function copyTree(src, dst)
    if not fs.exists(src) then return end
    if fs.isDir(src) then
        if not fs.exists(dst) then fs.makeDir(dst) end
        for _, name in ipairs(fs.list(src)) do
            copyTree(src.."/"..name, dst.."/"..name)
        end
    else
        if fs.exists(dst) then fs.delete(dst) end
        local ok = pcall(fs.copy, src, dst)
        if ok then term.write(".") end
    end
end

for _, dir in ipairs({"kernel","bin","sbin","lib","bios","bootloader","de","etc"}) do
    if fs.exists(backupPath.."/"..dir) then
        copyTree(backupPath.."/"..dir, "/"..dir)
    end
end
if fs.exists(backupPath.."/startup.lua") then
    if fs.exists("/startup.lua") then fs.delete("/startup.lua") end
    fs.copy(backupPath.."/startup.lua", "/startup.lua")
end

print("")
setColor(colors.green)
print("Restore complete! Rebooting in 3 seconds...")
setColor(colors.white)
os.sleep(3)
os.reboot()
return 0
