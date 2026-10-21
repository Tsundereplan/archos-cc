--[[
    kernel/craftos-shim.lua  —  CraftOS 1.9 vanilla shim
    ===================================================
    Boots into vanilla CraftOS shell, bypassing ArchOS-CC.

    Approach: we can't just `os.run(_G, "/rom/programs/shell.lua")`
    because ArchOS-CC has polluted _G with Kernel.*, Process.*, etc.
    which break the vanilla shell's require() (loop in gettable).

    Instead we use a marker file: /tmp/boot-craftos-once
    1. We create the marker file.
    2. We reboot.
    3. On next boot, startup.lua sees the marker and:
       - Deletes the marker (one-shot)
       - Launches the vanilla CraftOS shell directly, bypassing
         the bootloader and ArchOS kernel entirely.
    4. When the user types 'exit' in the vanilla shell, CC:Tweaked
       reboots the computer normally, and ArchOS-CC loads again.
]]

-- Reset terminal
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1, 1)

if term.isColor() then
    term.setTextColor(colors.lightGray)
end
print("    CraftOS 1.9.2  -  vanilla shell mode")
print("    ======================================")
print("")
if term.isColor() then
    term.setTextColor(colors.white)
end

-- Create marker file so startup.lua knows to launch vanilla shell
if not fs.exists("/tmp") then fs.makeDir("/tmp") end
local f = fs.open("/tmp/boot-craftos-once", "w")
if f then
    f.write("1")
    f.close()
end

print("Booting vanilla CraftOS shell ...")
print("(ArchOS-CC will reload on next reboot)")
print("")
os.sleep(1)
os.reboot()
