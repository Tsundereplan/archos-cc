-- bin/chmod.lua  —  Change file mode bits
local FS = _G.FS
local Permissions = _G.Permissions
local args = {...}

if #args < 2 then
    print("Usage: chmod MODE FILE...")
    print("  MODE = octal number (e.g. 755, 644, 700)")
    print("  FILE = file or directory to change")
    return 1
end

local mode = tonumber(args[1], 8)
if not mode then
    io.stderr:write("chmod: invalid mode: '" .. args[1] .. "'\n")
    return 1
end

local ret = 0
for i = 2, #args do
    local path = args[i]
    if FS then path = FS.normalize(path) end
    if not fs.exists(path) then
        io.stderr:write("chmod: cannot access '" .. args[i] .. "': No such file or directory\n")
        ret = 1
    else
        if Permissions then
            local info = Permissions.get(path) or { uid = 0, gid = 0, mode = 644 }
            Permissions.set(path, info.uid, info.gid, mode)
        else
            -- Without permissions lib, just store in metadata
        end
    end
end
return ret
