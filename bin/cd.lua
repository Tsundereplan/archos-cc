-- bin/cd.lua  —  Change directory (this is just a fallback; cd is a builtin in sh.lua)
local FS = _G.FS or (fs.exists("/lib/fs.lua") and dofile("/lib/fs.lua"))
local Kernel = _G.Kernel

local target = arg and arg[1] or (Kernel and Kernel.getEnv("HOME") or "/root")
if target == "" then target = (Kernel and Kernel.getEnv("HOME") or "/root") end

if target == "~" then
    target = Kernel and Kernel.getEnv("HOME") or "/root"
elseif target:sub(1, 2) == "~/" then
    target = (Kernel and Kernel.getEnv("HOME") or "/root") .. target:sub(2)
end

if FS then target = FS.normalize(target) end
if not fs.exists(target) then
    io.stderr:write("cd: " .. arg[1] .. ": No such file or directory\n")
    return 1
end
if not fs.isDir(target) then
    io.stderr:write("cd: " .. arg[1] .. ": Not a directory\n")
    return 1
end
Kernel.setCwd(target)
return 0
