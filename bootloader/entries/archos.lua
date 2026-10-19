-- /bootloader/entries/archos.lua
-- ArchOS-CC boot entry
return {
    name        = "ArchOS-CC",
    kernel      = "/kernel/init.lua",
    init        = "/sbin/init.lua",
    description = "Arch Linux style OS for ComputerCraft: Tweaked",
    args        = {
        target = "multi-user",
        -- target = "graphical" for direct GUI boot
    }
}
