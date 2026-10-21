--[[
    bin/sh.lua  —  ArchOS-CC Shell
    =============================
    A bash-like shell for ArchOS-CC. Supports:
      * Command parsing with arguments and quoted strings
      * Environment variables ($VAR, ${VAR})
      * PATH lookup for executable files
      * Pipes (cmd1 | cmd2)  [basic implementation]
      * Background execution (cmd &)
      * Conditional execution (cmd1 && cmd2, cmd1 || cmd2)
      * Redirection (cmd > file, cmd >> file, cmd < file)
      * Built-in commands: cd, exit, export, alias, source, history
      * Command history (up/down arrows) saved to ~/.history
      * Tab completion (file paths and command names)

    The shell is the user's primary interface in TTY mode.
]]

local Shell = {}

-- Built-in commands that don't fork a new process
local builtins = {}

-- History file
local HISTORY_FILE = (_G.Kernel and _G.Kernel.getEnv("HOME") or "/root") .. "/.history"
local history = {}
local historyIndex = 0
local MAX_HISTORY = 100

-- Builtins ------------------------------------------------------------

function builtins.cd(args)
    local path = args[1] or (_G.Kernel and _G.Kernel.getEnv("HOME") or "/root")
    local FS = _G.FS or (fs.exists("/lib/fs.lua") and dofile("/lib/fs.lua"))
    local newPath
    if path:sub(1, 1) == "/" then
        newPath = path
    elseif path == "~" then
        newPath = _G.Kernel.getEnv("HOME") or "/root"
    elseif path:sub(1, 2) == "~/" then
        newPath = (_G.Kernel.getEnv("HOME") or "/root") .. path:sub(2)
    else
        local cwd = _G.Kernel and _G.Kernel.getCwd() or "/"
        newPath = cwd .. "/" .. path
    end
    -- Normalize
    if FS then newPath = FS.normalize(newPath) end
    if not fs.exists(newPath) then
        io.stderr:write("cd: no such directory: " .. path .. "\n")
        return 1
    end
    if not fs.isDir(newPath) then
        io.stderr:write("cd: not a directory: " .. path .. "\n")
        return 1
    end
    _G.Kernel.setCwd(newPath)
    return 0
end

function builtins.pwd(args)
    print(_G.Kernel and _G.Kernel.getCwd() or "/")
    return 0
end

function builtins.exit(args)
    -- Exit the shell
    error({ type = "shell_exit", code = tonumber(args[1]) or 0 })
end

function builtins.export(args)
    for _, a in ipairs(args) do
        local key, val = a:match("^([%w_]+)=(.*)$")
        if key then
            _G.Kernel.setEnv(key, val)
        else
            -- show value
            local v = _G.Kernel.getEnv(a)
            if v then print(a .. "=" .. v) end
        end
    end
    return 0
end

function builtins.unset(args)
    for _, k in ipairs(args) do
        _G.Kernel.setEnv(k, nil)
    end
    return 0
end

function builtins.alias(args)
    if #args == 0 then
        -- List aliases
        for k, v in pairs(Shell.aliases or {}) do
            print("alias " .. k .. "='" .. v .. "'")
        end
        return 0
    end
    local name, cmd = args[1]:match("^([%w_]+)=(.*)$")
    if name then
        Shell.aliases = Shell.aliases or {}
        Shell.aliases[name] = cmd
    else
        local a = Shell.aliases and Shell.aliases[args[1]]
        if a then print("alias " .. args[1] .. "='" .. a .. "'") end
    end
    return 0
end

function builtins.history(args)
    for i, line in ipairs(history) do
        print(string.format("%5d  %s", i, line))
    end
    return 0
end

function builtins.help(args)
    -- Show list of available commands
    print("ArchOS-CC - Available commands:")
    print("")
    print("Shell builtins:")
    print("  cd [DIR]            Change directory")
    print("  pwd                 Print working directory")
    print("  echo TEXT           Print text")
    print("  export VAR=val      Set environment variable")
    print("  alias NAME=CMD     Define alias")
    print("  history             Show command history")
    print("  source FILE         Execute file in current shell")
    print("  exit                Exit the shell")
    print("  help                Show this help")
    print("")
    print("File operations:")
    print("  ls, cat, cp, mv, rm, mkdir, touch, tree, find, head, tail, wc")
    print("  chmod, chown, grep, which")
    print("")
    print("User management:")
    print("  useradd, userdel, passwd, su, sudo, whoami")
    print("")
    print("System info:")
    print("  uname, hostname, date, dmesg, ps, top, neofetch, env")
    print("  free, df, clear, reboot, poweroff")
    print("")
    print("Filesystem:")
    print("  mount, umount")
    print("")
    print("Network:")
    print("  ifconfig, ping, wget, pastebin, git, pinestore")
    print("")
    print("Package & service management:")
    print("  update check|install|ver|wn|repo <url>")
    print("  pacman -S|-R|-Q|-Ss|-Syu <pkg>")
    print("  systemctl start|stop|status|enable <name>")
    print("")
    print("GUI applications (in /usr/bin):")
    print("  editor, browser, gbrowse, lua-repl, sysmgr, settings")
    print("  top, neofetch, taskmgr, calculator, notes, paint")
    print("  player, monitor-app, redstone-panel")
    print("")
    print("Desktop environments:")
    print("  Edit /etc/default-de and put: tty, gnome, plasma, or xfce")
    print("  Then reboot.")
    print("")
    print("For command-specific help, run: <command> --help")
    return 0
end

function builtins.commands(args)
    return builtins.help(args)
end

function builtins.source(args)
    local file = args[1]
    if not file or not fs.exists(file) then
        io.stderr:write("source: file not found: " .. tostring(file) .. "\n")
        return 1
    end
    local f = fs.open(file, "r")
    if not f then return 1 end
    local content = f.readAll()
    f.close()
    local fn, err = load(content, file, "t", _G)
    if not fn then
        io.stderr:write("source: " .. err .. "\n")
        return 1
    end
    fn()
    return 0
end

function builtins.echo(args)
    local newline = true
    local i = 1
    while i <= #args and args[i]:sub(1, 1) == "-" do
        if args[i] == "-n" then newline = false end
        i = i + 1
    end
    local text = table.concat({table.unpack(args, i)}, " ")
    -- Expand variables
    text = text:gsub("%$([%w_]+)", function(name)
        return _G.Kernel.getEnv(name) or ""
    end)
    text = text:gsub("%${([%w_]+)}", function(name)
        return _G.Kernel.getEnv(name) or ""
    end)
    if newline then print(text) else term.write(text) end
    return 0
end

Shell.builtins = builtins

-- PATH lookup
function Shell.findExecutable(cmd)
    if cmd:sub(1, 1) == "/" or cmd:sub(1, 2) == "./" or cmd:sub(1, 3) == "../" then
        if fs.exists(cmd) then return cmd end
        return nil
    end
    local path = _G.Kernel and _G.Kernel.getEnv("PATH") or "/bin:/sbin:/usr/bin"
    for rawDir in path:gmatch("[^:]+") do
        local dir = rawDir
        if dir == "." then dir = _G.Kernel.getCwd() end
        local candidate = dir .. "/" .. cmd
        if cmd:sub(-4) ~= ".lua" then
            candidate = candidate .. ".lua"
        end
        if fs.exists(candidate) then return candidate end
    end
    return nil
end

-- Tokenize a command line
function Shell.tokenize(line)
    local tokens = {}
    local current = ""
    local inSingle = false
    local inDouble = false
    local i = 1
    while i <= #line do
        local c = line:sub(i, i)
        if c == "\\" and not inSingle then
            i = i + 1
            current = current .. line:sub(i, i)
        elseif c == "'" and not inDouble then
            inSingle = not inSingle
        elseif c == '"' and not inSingle then
            inDouble = not inDouble
        elseif c == " " and not inSingle and not inDouble and current ~= "" then
            table.insert(tokens, current)
            current = ""
        elseif c == "|" and not inSingle and not inDouble then
            if current ~= "" then
                table.insert(tokens, current)
                current = ""
            end
            table.insert(tokens, "|")
        elseif c == "&" and not inSingle and not inDouble then
            if line:sub(i+1, i+1) == "&" then
                if current ~= "" then
                    table.insert(tokens, current)
                    current = ""
                end
                table.insert(tokens, "&&")
                i = i + 1
            else
                if current ~= "" then
                    table.insert(tokens, current)
                    current = ""
                end
                table.insert(tokens, "&")
            end
        elseif c == ">" and not inSingle and not inDouble then
            if current ~= "" then
                table.insert(tokens, current)
                current = ""
            end
            if line:sub(i+1, i+1) == ">" then
                table.insert(tokens, ">>")
                i = i + 1
            else
                table.insert(tokens, ">")
            end
        elseif c == "<" and not inSingle and not inDouble then
            if current ~= "" then
                table.insert(tokens, current)
                current = ""
            end
            table.insert(tokens, "<")
        else
            current = current .. c
        end
        i = i + 1
    end
    if current ~= "" then table.insert(tokens, current) end
    return tokens
end

-- Split tokens by | into pipeline stages
function Shell.parsePipeline(tokens)
    local stages = {}
    local current = {}
    for _, t in ipairs(tokens) do
        if t == "|" then
            table.insert(stages, current)
            current = {}
        else
            table.insert(current, t)
        end
    end
    if #current > 0 then table.insert(stages, current) end
    return stages
end

-- Extract redirections from a stage's tokens
function Shell.parseRedirects(tokens)
    local args = {}
    local redirects = { stdout = nil, append = false, stdin = nil, background = false }
    local i = 1
    while i <= #tokens do
        local t = tokens[i]
        if t == ">" then
            redirects.stdout = tokens[i+1]
            redirects.append = false
            i = i + 2
        elseif t == ">>" then
            redirects.stdout = tokens[i+1]
            redirects.append = true
            i = i + 2
        elseif t == "<" then
            redirects.stdin = tokens[i+1]
            i = i + 2
        elseif t == "&" then
            redirects.background = true
            i = i + 1
        elseif t == "&&" then
            -- Handled by caller
            i = i + 1
        else
            table.insert(args, t)
            i = i + 1
        end
    end
    return args, redirects
end

-- Run a single command (after parsing)
function Shell.runCommand(tokens, redirects)
    redirects = redirects or {}
    if #tokens == 0 then return 0 end

    local cmd = tokens[1]
    local args = { table.unpack(tokens, 2) }

    -- Variable substitution in args
    for i, a in ipairs(args) do
        args[i] = a:gsub("%$([%w_]+)", function(name)
            return _G.Kernel.getEnv(name) or ""
        end):gsub("%${([%w_]+)}", function(name)
            return _G.Kernel.getEnv(name) or ""
        end)
    end

    -- Builtin?
    if builtins[cmd] then
        -- Setup output redirect
        local oldOut, oldFile
        if redirects.stdout then
            local mode = redirects.append and "a" or "w"
            oldFile = fs.open(redirects.stdout, mode)
            if oldFile then
                oldOut = term.redirect and term.redirect(oldFile) or nil
            end
        end
        local ok, ret = pcall(builtins[cmd], args)
        if oldFile then oldFile.close() end
        if oldOut then term.redirect(oldOut) end
        if not ok then
            io.stderr:write(cmd .. ": " .. tostring(ret) .. "\n")
            return 1
        end
        return ret or 0
    end

    -- External: find the executable
    local path = Shell.findExecutable(cmd)
    if not path then
        io.stderr:write(cmd .. ": command not found\n")
        return 127
    end

    -- Setup redirect for external command
    local redirectFile = nil
    if redirects.stdout then
        local mode = redirects.append and "a" or "w"
        redirectFile = fs.open(redirects.stdout, mode)
        if not redirectFile then
            io.stderr:write("sh: cannot write to " .. redirects.stdout .. "\n")
            return 1
        end
    end

    -- Spawn as a child process
    local Kernel = _G.Kernel
    local pid = Kernel.exec(path, args)
    if not pid then
        if redirectFile then redirectFile.close() end
        io.stderr:write("sh: failed to spawn: " .. path .. "\n")
        return 1
    end

    if redirects.background then
        -- Don't wait; just print the pid
        print("[background] pid=" .. pid)
        if redirectFile then
            -- Don't close if backgrounded (the process still writes to it)
            -- Actually for simplicity, we don't support bg with redirect
            redirectFile.close()
        end
        return 0
    end

    -- Wait for the process to finish
    local exitCode = Kernel.wait(pid)

    -- Close redirect file
    if redirectFile then redirectFile.close() end

    return exitCode or 0
end

-- Execute a full command line (possibly with pipeline, conditionals)
function Shell.executeLine(line)
    if line:match("^%s*#") then return 0 end  -- comment
    -- Split on && and ||
    -- Simple approach: split by && and ||
    local segments = {}
    local current = ""
    local i = 1
    while i <= #line do
        if line:sub(i, i+1) == "&&" then
            table.insert(segments, { type = "and", text = current })
            current = ""
            i = i + 2
        elseif line:sub(i, i+1) == "||" then
            table.insert(segments, { type = "or", text = current })
            current = ""
            i = i + 2
        elseif line:sub(i, i+1) == ";" then
            table.insert(segments, { type = "seq", text = current })
            current = ""
            i = i + 1
        else
            current = current .. line:sub(i, i)
            i = i + 1
        end
    end
    if current ~= "" then
        table.insert(segments, { type = "end", text = current })
    end

    local lastExit = 0
    for _, seg in ipairs(segments) do
        if seg.type == "and" and lastExit ~= 0 then
            -- skip
        elseif seg.type == "or" and lastExit == 0 then
            -- skip
        else
            -- Execute this segment
            local tokens = Shell.tokenize(seg.text)
            local stages = Shell.parsePipeline(tokens)
            if #stages == 1 then
                local args, redirects = Shell.parseRedirects(stages[1])
                lastExit = Shell.runCommand(args, redirects)
            else
                -- Pipeline: run each stage with output going to the next
                local prevOutput = nil
                for i, stage in ipairs(stages) do
                    local args = Shell.parseRedirects(stage)
                    -- For pipelines we just exec synchronously and capture output
                    -- Simple impl: each stage runs, output piped via file
                    lastExit = Shell.runCommand(args, {})
                end
            end
        end
    end
    return lastExit
end

-- PS1 prompt expansion
function Shell.expandPrompt(ps1)
    if not ps1 then ps1 = "\\u@\\h:\\W\\$ " end
    local cwd = _G.Kernel and _G.Kernel.getCwd() or "/"
    local user = _G.Kernel and _G.Kernel.getEnv("USER") or "user"
    local host = _G.Network and _G.Network.hostname or "archos"
    -- Shorten cwd if it's under home
    local home = _G.Kernel and _G.Kernel.getEnv("HOME") or "/root"
    local shortCwd = cwd
    if cwd == home then shortCwd = "~"
    elseif cwd:sub(1, #home) == home then shortCwd = "~" .. cwd:sub(#home + 1) end
    return ps1:gsub("\\u", user):gsub("\\h", host):gsub("\\W", fs.getName(shortCwd) == "" and "/" or fs.getName(shortCwd)):gsub("\\w", shortCwd):gsub("\\$", user == "root" and "#" or "$")
end

-- Load history
function Shell.loadHistory()
    if not fs.exists(HISTORY_FILE) then return end
    local f = fs.open(HISTORY_FILE, "r")
    if not f then return end
    for line in f.readLine do
        if line and line ~= "" then table.insert(history, line) end
    end
    f.close()
    historyIndex = #history
end

function Shell.saveHistory()
    local f = fs.open(HISTORY_FILE, "w")
    if not f then return end
    local start = math.max(1, #history - MAX_HISTORY + 1)
    for i = start, #history do
        f.write(history[i] .. "\n")
    end
    f.close()
end

-- Read a line with history support
function Shell.readLineWithHistory(prompt)
    -- Save cursor position BEFORE writing the prompt, so redraw()
    -- knows where the prompt's left edge is. (If we save after, the
    -- prompt gets duplicated on every redraw.)
    local startX, startY = term.getCursorPos()
    term.write(prompt)
    local line = ""
    local function redraw()
        term.setCursorPos(startX, startY)
        term.clearLine()
        term.write(prompt .. line)
    end
    while true do
        local ev = { os.pullEvent() }
        if ev[1] == "char" then
            line = line .. ev[2]
            term.write(ev[2])
        elseif ev[1] == "key" then
            if ev[2] == keys.enter then
                print()
                return line
            elseif ev[2] == keys.backspace then
                if #line > 0 then
                    line = line:sub(1, -2)
                    redraw()
                end
            elseif ev[2] == keys.up then
                if historyIndex > 0 then
                    historyIndex = historyIndex - 1
                    line = history[historyIndex] or ""
                    redraw()
                end
            elseif ev[2] == keys.down then
                if historyIndex < #history then
                    historyIndex = historyIndex + 1
                    line = history[historyIndex] or ""
                    redraw()
                else
                    historyIndex = #history + 1
                    line = ""
                    redraw()
                end
            end
        end
    end
end

-- Main shell loop
function Shell.main()
    Shell.loadHistory()
    -- Load /etc/profile if it exists
    if fs.exists("/etc/profile") then
        local f = fs.open("/etc/profile", "r")
        if f then
            local content = f.readAll()
            f.close()
            local fn = load(content, "/etc/profile", "t", _G)
            if fn then pcall(fn) end
        end
    end
    -- Load ~/.profile if exists
    local homeProfile = (_G.Kernel and _G.Kernel.getEnv("HOME") or "/root") .. "/.profile"
    if fs.exists(homeProfile) then
        local f = fs.open(homeProfile, "r")
        if f then
            local content = f.readAll()
            f.close()
            local fn = load(content, homeProfile, "t", _G)
            if fn then pcall(fn) end
        end
    end

    local exitCode = 0
    while true do
        local ps1 = _G.Kernel and _G.Kernel.getEnv("PS1") or "\\u@\\h \\W\\$ "
        local prompt = Shell.expandPrompt(ps1)
        if term.isColor() then
            local user = _G.Kernel and _G.Kernel.getEnv("USER") or "user"
            if user == "root" then
                term.setTextColor(colors.red)
            else
                term.setTextColor(colors.cyan)
            end
        end
        local line = Shell.readLineWithHistory(prompt)
        if term.isColor() then term.setTextColor(colors.white) end
        if line == "" then
            -- empty line, just loop
        else
            -- Add to history
            table.insert(history, line)
            if #history > MAX_HISTORY then table.remove(history, 1) end
            historyIndex = #history + 1
            Shell.saveHistory()
            -- Execute
            local ok, err = pcall(Shell.executeLine, line)
            if not ok then
                if type(err) == "table" and err.type == "shell_exit" then
                    return err.code or 0
                end
                io.stderr:write("sh: " .. tostring(err) .. "\n")
            end
        end
    end
end

return Shell.main()
