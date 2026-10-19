-- bin/cat.lua  —  Concatenate files to stdout
-- Usage: cat [FILE]...  (use - for stdin, not yet supported)
--       cat -n FILE    number all output lines

local FS = _G.FS
local args = {...}
local opts = { number = false }
local files = {}

for _, a in ipairs(args) do
    if a == "-n" or a == "--number" then opts.number = true
    elseif a == "--help" then
        print("Usage: cat [OPTION]... [FILE]...")
        print("Concatenate FILE(s) to standard output.")
        print("  -n, --number    number all output lines")
        return 0
    else
        table.insert(files, a)
    end
end

if #files == 0 then
    -- Read from stdin (we don't have real stdin support yet; just error)
    io.stderr:write("cat: no input files\n")
    return 1
end

local Kernel = _G.Kernel
local lineNum = 1
local ret = 0
for _, file in ipairs(files) do
    local real = FS and FS.resolve(file) or file
    if not fs.exists(real) then
        io.stderr:write("cat: " .. file .. ": No such file or directory\n")
        ret = 1
    elseif fs.isDir(real) then
        io.stderr:write("cat: " .. file .. ": Is a directory\n")
        ret = 1
    else
        local f = fs.open(real, "r")
        if not f then
            io.stderr:write("cat: " .. file .. ": Cannot open file\n")
            ret = 1
        else
            local content = f.readAll()
            f.close()
            if opts.number then
                for line in (content or ""):gmatch("[^\n]*") do
                    print(string.format("%6d  %s", lineNum, line))
                    lineNum = lineNum + 1
                end
            else
                if content and content:sub(-1) == "\n" then
                    io.write(content)
                else
                    print(content or "")
                end
            end
        end
    end
end
return ret
