# Development Guide

This document describes how to develop, modify, and extend ArchOS-CC.

## Code style

* Use **Lua 5.1 syntax** (CC:Tweaked's Cobalt runtime).
* No bitwise operators (`&`, `|`, `~`, `<<`, `>>`) — use `bit32` API or
  arithmetic equivalents. (Note: some kernel files use them — those are
  bugs to be fixed.)
* Indent with 4 spaces. No tabs.
* Maximum line length: 100 characters.
* Use `local` for all variables and functions, unless you really need
  them in `_G`.
* File header:
  ```lua
  --[[
      path/to/file.lua  —  One-line description
      ============================================
      Longer description if needed.
  ]]
  ```

## Adding a new bin command

1. Create `/bin/<name>.lua`.
2. Start with the header:
   ```lua
   -- bin/name.lua  —  Description
   local args = arg or {...}
   -- ... parse args ...
   -- ... do work ...
   return 0  -- or non-zero on error
   ```
3. Use `_G.Kernel` for process/env access, `_G.FS` for files,
   `_G.Users` for users, etc.
4. Use `io.stderr:write()` for error messages (not `print()`).
5. Test by running `<name>` from the shell.

## Adding a new usr/bin app

Same as bin commands, but typically interactive (TUI or GUI).

For TUI apps, the typical structure:

```lua
local function render()
    term.clear()
    -- ... draw screen ...
end

local function main()
    while true do
        render()
        local ev = { os.pullEvent() }
        if ev[1] == "key" and ev[2] == keys.q then
            break
        elseif ev[1] == "char" then
            -- handle character input
        elseif ev[1] == "mouse_click" then
            -- handle mouse click
        end
    end
end

return main()
```

For GUI apps, use `paintutils.drawPixel`, `paintutils.drawLine`,
`paintutils.drawBox`, `paintutils.drawFilledBox`, `paintutils.loadImage`,
`paintutils.drawImage`.

## Adding a new driver

1. Create `/lib/drivers/<name>.lua`.
2. Implement at minimum:
   ```lua
   local Driver = {}
   function Driver.onAttach(side, wrap)
       -- Called when peripheral of this type is attached
   end
   function Driver.onDetach(side)
       -- Called when peripheral is detached
   end
   function Driver.init(hw)
       -- Called by PnP during kernel init, with the BIOS hw table
   end
   return Driver
   ```
3. Register it in `/lib/drivers/pnp.lua`:
   ```lua
   PnP.registerDriver("peripheral_type", dofile("/lib/drivers/<name>.lua"))
   ```

## Adding a systemd service

Create `/etc/systemd/system/<name>.service`:

```ini
[Unit]
Description=My Service
After=networkd.service

[Service]
Type=simple
ExecStart=/path/to/my/daemon.lua
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
```

Then enable and start it:

```bash
systemctl enable myservice
systemctl start myservice
```

## Adding a desktop environment

1. Create `/de/<name>.lua`.
2. Implement a `main()` function that takes over the screen and runs an
   event loop.
3. The DE is launched by `/sbin/init.lua` if `/etc/default-de` contains
   the DE name.
4. To switch DE: `echo "<name>" > /etc/default-de` and reboot.

A minimal DE example:

```lua
-- de/myde.lua  —  My Custom Desktop
local function main()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    print("Welcome to MyDE")
    print("Press any key to exit")
    os.pullEvent("key")
end
return main()
```

## Testing

ArchOS-CC doesn't have a formal test suite yet. For manual testing:

1. Boot a CC:Tweaked Advanced Computer.
2. Run the installer.
3. Walk through the boot menu, BIOS setup, login, and desktop.
4. Verify each command works as documented.

To test individual Lua files without the OS:

```bash
# In the CC:Tweaked shell:
lua-repl  # then load the module via require/dofile
```

## Debugging

* **Boot log**: `/var/log/boot.log` contains BIOS, bootloader, and kernel
  init messages. Read with `dmesg` or `cat /var/log/boot.log`.
* **Process state**: `ps` shows all running processes and their states.
* **Kernel panic**: when init dies, the bootloader prints the error and
  halts. Boot into CraftOS via `F12` to inspect files.

## Adding packages to your GitHub repo

To create a package that can be installed via `pacman -S`:

1. Create a new GitHub repo (e.g. `archos-cc-packages`).
2. Create a `core.db` file with one line per package:
   ```
   hello|1.0.0|Hello world demo|https://raw.githubusercontent.com/you/archos-cc-packages/main/hello.lua|
   ```
3. Create the `hello.lua` installer:
   ```lua
   return {
       install = function(name, pkg)
           -- Write the actual program files
           local f = fs.open("/bin/hello.lua", "w")
           f.write('print("Hello, World!")\n')
           f.close()
           return { files = {"/bin/hello.lua"} }
       end
   }
   ```
4. Update `/lib/arch/pacman.lua` to point to your repo:
   ```lua
   config.repos = {
       { name = "core", url = "https://raw.githubusercontent.com/you/archos-cc-packages/main/core.db" },
   }
   ```
5. On the computer: `pacman -Sy && pacman -S hello`.

## Contributing back

If you build something cool (a new app, driver, or DE), consider opening
a PR upstream! The repo structure makes adding things straightforward.

## Known limitations

* Cooperative multitasking means a hung process blocks the whole system.
  Use `Ctrl+T` to terminate.
* No real security — the permission system is advisory, not enforced.
* HTTP API rate-limited by Minecraft server TPS.
* No persistent storage across computer ID changes (label changes don't
  affect files).
* bit32 API not available in pure Lua 5.1 — work around with arithmetic.
