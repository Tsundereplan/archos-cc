-- bin/echo.lua  —  Print text
local args = {...}
local newline = true
local i = 1
while i <= #args and args[i]:sub(1, 1) == "-" do
    if args[i] == "-n" then newline = false end
    i = i + 1
end
local text = table.concat({table.unpack(args, i)}, " ")
-- Variable expansion
text = text:gsub("%$([%w_]+)", function(name)
    return _G.Kernel and _G.Kernel.getEnv(name) or ""
end):gsub("%${([%w_]+)}", function(name)
    return _G.Kernel and _G.Kernel.getEnv(name) or ""
end)
if newline then
    print(text)
else
    term.write(text)
end
return 0
