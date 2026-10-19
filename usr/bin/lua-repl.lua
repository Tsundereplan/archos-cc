--[[
    usr/bin/lua-repl.lua  —  Interactive Lua REPL
    ============================================
    Like the default `lua` interpreter. Reads expressions, evaluates them,
    prints results. Supports multi-line statements via _G._REPL_HISTORY.

    Commands (start with .):
      .exit      quit
      .help      show help
      .vars      list current variables in _G
      .reload X   reload module X (require with cache clear)
      .! CMD     run shell command and print output
]]

local function setColor(c)
    if term.isColor() then term.setTextColor(c) end
end

local function printHeader()
    setColor(colors.lightBlue)
    print("    Lua REPL for ArchOS-CC")
    setColor(colors.gray)
    print("    Lua 5.1 / CC:Tweaked")
    print("    Type .help for commands, .exit to quit")
    print("")
    setColor(colors.white)
end

local function showHelp()
    print([[
Commands:
  .exit        Exit the REPL
  .help        Show this help
  .vars        List all global variables
  .reload X    Reload module X (re-require)
  .! CMD       Run shell command (e.g. .! ls)
  =expr        Print result of expression (e.g. =1+2)
  <ENTER>      Run statement or expression
]])
end

-- Run a shell command and capture output (basic)
local function runShellCommand(cmd)
    local path = nil
    local PATH = _G.Kernel and _G.Kernel.getEnv("PATH") or "/bin"
    for dir in PATH:gmatch("[^:]+") do
        local candidate = dir .. "/" .. cmd:match("%S+")
        if cmd:match("%S+") and cmd:match("%S+"):sub(-4) ~= ".lua" then
            candidate = candidate .. ".lua"
        end
        if fs.exists(candidate) then path = candidate break end
    end
    if not path then
        print("command not found: " .. cmd:match("%S+"))
        return
    end
    local Kernel = _G.Kernel
    local pid = Kernel.exec(path, {})
    if pid then Kernel.wait(pid) end
end

local function listVars()
    local names = {}
    for k, v in pairs(_G) do
        if type(k) == "string" and k:sub(1, 1) ~= "_" then
            table.insert(names, k)
        end
    end
    table.sort(names)
    for _, n in ipairs(names) do
        local v = _G[n]
        local t = type(v)
        local preview
        if t == "string" then preview = '"' .. v:sub(1, 30) .. (#v > 30 and '...' or '') .. '"'
        elseif t == "number" or t == "boolean" then preview = tostring(v)
        elseif t == "table" then preview = "[table]"
        elseif t == "function" then preview = "[function]"
        else preview = "[" .. t .. "]" end
        print(string.format("  %-25s %-10s %s", n, t, preview))
    end
end

local function main()
    printHeader()

    local buffer = ""
    local multiline = false

    -- REPL state: persistent across the session
    _G._REPL_HISTORY = _G._REPL_HISTORY or {}

    while true do
        setColor(colors.green)
        if multiline then
            term.write(">> ")
        else
            term.write("> ")
        end
        setColor(colors.white)
        local line = read()

        if not line then break end  -- Ctrl+D / EOF

        -- Special REPL commands
        if line:sub(1, 1) == "." then
            local cmd = line:sub(2)
            if cmd == "exit" or cmd == "quit" then
                break
            elseif cmd == "help" then
                showHelp()
            elseif cmd == "vars" then
                listVars()
            elseif cmd:sub(1, 1) == "!" then
                runShellCommand(cmd:sub(2))
            elseif cmd:sub(1, 7) == "reload " then
                local modname = cmd:sub(8):gsub("^%s+", ""):gsub("%s+$", "")
                package.loaded[modname] = nil
                local ok, mod = pcall(require, modname)
                if ok then
                    print("reloaded: " .. modname)
                else
                    print("error: " .. tostring(mod))
                end
            else
                print("unknown command: " .. cmd .. "  (try .help)")
            end
        elseif line:sub(1, 1) == "=" then
            -- Expression: print result
            local expr = line:sub(2)
            local fn, err = load("return " .. expr, "REPL", "t", _G)
            if fn then
                local ok, result = pcall(fn)
                if ok then
                    if type(result) == "table" then
                        print(textutils.serialize(result))
                    else
                        print(tostring(result))
                    end
                else
                    setColor(colors.red)
                    print("error: " .. tostring(result))
                    setColor(colors.white)
                end
            else
                setColor(colors.red)
                print("compile error: " .. tostring(err))
                setColor(colors.white)
            end
        else
            -- Accumulate lines for multi-line statements
            buffer = buffer .. (buffer == "" and "" or "\n") .. line
            -- Try to compile as expression or statement
            local fn, err = load(buffer, "REPL", "t", _G)
            if fn then
                -- Successfully compiled; execute
                local ok, result = pcall(fn)
                if not ok then
                    setColor(colors.red)
                    print("runtime: " .. tostring(result))
                    setColor(colors.white)
                elseif result ~= nil then
                    print(tostring(result))
                end
                buffer = ""
                multiline = false
            else
                -- Check if error is just "unexpected EOF" (incomplete input)
                if err and err:match("<eof>") then
                    multiline = true
                else
                    setColor(colors.red)
                    print("error: " .. tostring(err))
                    setColor(colors.white)
                    buffer = ""
                    multiline = false
                end
            end
        end
    end

    setColor(colors.gray)
    print("bye.")
    setColor(colors.white)
    return 0
end

return main()
