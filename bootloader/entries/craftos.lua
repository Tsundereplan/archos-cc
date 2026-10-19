-- /bootloader/entries/craftos.lua
-- Boot entry for the standard CraftOS 1.9 shell.
-- This loads /kernel/craftos-shim.lua which simply hands control
-- to the native /rom/programs/shell.lua (the vanilla CraftOS shell).
return {
    name        = "CraftOS 1.9",
    kernel      = "/kernel/craftos-shim.lua",
    description = "Boot into the standard CraftOS 1.9 shell (no ArchOS)",
    args        = {}
}
