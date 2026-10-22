--[[
    kernel/craftos-shim.lua  —  CraftOS 1.9 vanilla shim (v3)
    ===================================================
    Reboots into vanilla CraftOS by temporarily renaming
    /startup.lua to /startup.lua.bak. On next boot, CC:Tweaked
    has no startup.lua and runs the default /rom/programs/shell.lua
    with a completely clean _G.

    When the user types 'exit' in vanilla shell, CC:T reboots.
    On next boot, startup.lua.bak is restored automatically by
    a special marker file /tmp/restore-startup.
]]

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

if term.isColor() then term.setTextColor(colors.lightGray) end
print("    CraftOS 1.9  -  vanilla shell mode")
print("    ================================")
print("")
if term.isColor() then term.setTextColor(colors.white) end

-- Move /startup.lua aside
if fs.exists("/startup.lua") then
    if fs.exists("/startup.lua.bak") then
        fs.delete("/startup.lua.bak")
    end
    fs.move("/startup.lua", "/startup.lua.bak")
    -- Create restore marker
    if not fs.exists("/tmp") then fs.makeDir("/tmp") end
    local f = fs.open("/tmp/restore-startup", "w")
    if f then f.write("1"); f.close() end
    print("[OK] Moved /startup.lua -> /startup.lua.bak")
else
    print("[INFO] /startup.lua not found - already in vanilla mode")
end

print("")
print("Rebooting into vanilla CraftOS in 2 seconds...")
print("(ArchOS-CC will be restored on next reboot)")
os.sleep(2)
os.reboot()
