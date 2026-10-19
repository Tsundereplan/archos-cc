-- bin/whoami.lua  —  Print the current effective user name
-- Usage: whoami

local Kernel = _G.Kernel
local args = {...}
if not args or #args == 0 then args = arg or {} end

if args[1] == "--help" or args[1] == "-h" then
    io.write("Usage: whoami\n")
    io.write("Print the user name associated with the current effective user ID.\n")
    return 0
end

-- Prefer the kernel-tracked USER env var; fall back to the process user record
local user = nil
if Kernel then
    if Kernel.getEnv then user = Kernel.getEnv("USER") end
    if (not user or user == "") and Kernel.getuser then
        user = Kernel.getuser()
    end
end

io.write((user or "root") .. "\n")
return 0
