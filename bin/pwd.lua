-- bin/pwd.lua  —  Print working directory
print(_G.Kernel and _G.Kernel.getCwd() or "/")
return 0
