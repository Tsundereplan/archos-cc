--[[
    kernel/craftos-shim.lua  —  CraftOS 1.9 vanilla shim (v3)
    ===================================================
    Moves /startup.lua aside and reboots. CC:T boots vanilla
    shell with clean _G. On next boot, startup.lua is restored.
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

if fs.exists("/startup.lua") then
    if fs.exists("/startup.lua.bak") then
        fs.delete("/startup.lua.bak")
    end
    fs.move("/startup.lua", "/startup.lua.bak")
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
