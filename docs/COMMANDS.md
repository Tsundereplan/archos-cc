# Command Reference

This is a reference for all the commands shipped with ArchOS-CC.

## Shell builtins

These commands are implemented inside `/bin/sh.lua` and don't spawn a
new process:

| Command    | Description                                                  |
|------------|--------------------------------------------------------------|
| `cd [DIR]` | Change working directory. `cd` with no args goes to `$HOME`. |
| `pwd`      | Print working directory.                                     |
| `exit [N]` | Exit the shell with status N (default 0).                    |
| `export VAR=val` | Set an environment variable.                          |
| `unset VAR` | Unset an environment variable.                              |
| `alias name=cmd` | Define a command alias.                                |
| `history`  | Print the command history.                                  |
| `source FILE` | Execute a file in the current shell context.             |
| `echo TEXT` | Print TEXT to stdout (with variable expansion).            |

## File operations

| Command | Description |
|---------|-------------|
| `ls [-a] [-l] [-h] [-R] [-1] [FILE]...` | List directory contents |
| `cd [DIR]` | Change directory |
| `pwd` | Print working directory |
| `cat [-n] [FILE]...` | Concatenate files to stdout |
| `cp [-r] [-v] [-f] SOURCE... DEST` | Copy files |
| `mv [-v] [-f] SOURCE... DEST` | Move/rename files |
| `rm [-r] [-f] [-v] FILE...` | Remove files/dirs |
| `mkdir [-p] [-v] DIR...` | Create directories |
| `touch [-c] FILE...` | Create empty file or update timestamps |
| `chmod MODE FILE...` | Change file mode (e.g. `chmod 755 script.lua`) |
| `chown OWNER[:GROUP] FILE...` | Change file owner |
| `tree [-L N] [-a] [-d] [DIR]` | Show tree view of a directory |
| `find [PATH] [-name PAT] [-type f\|d]` | Find files |
| `head [-n N] [FILE]...` | Show first N lines (default 10) |
| `tail [-n N] [FILE]...` | Show last N lines (default 10) |
| `wc [-l] [-w] [-c] [FILE]...` | Count lines/words/chars |
| `grep [-i] [-n] [-v] [-r] [-c] PATTERN FILE...` | Search for pattern |
| `which COMMAND` | Locate a command in PATH |
| `env` | Show environment variables |

## User management

| Command | Description |
|---------|-------------|
| `useradd [-m] [-d DIR] [-s SHELL] [-u UID] [-g GID] USERNAME` | Create a user |
| `userdel [-r] USERNAME` | Delete a user (and optionally home dir) |
| `passwd [USERNAME]` | Change password |
| `su [USERNAME]` | Switch user |
| `sudo [-u USER] COMMAND` | Run command as root (or another user) |
| `whoami` | Print current username |

## System information

| Command | Description |
|---------|-------------|
| `uname [-a] [-s] [-n] [-r] [-m] [-p]` | Print system information |
| `hostname [NAME]` | Print or set the hostname |
| `date [+FORMAT]` | Print current date/time |
| `dmesg [--clear]` | Print boot log |
| `ps` | List processes |
| `top` | Live process monitor (interactive) |
| `kill [-9\|-15\|-HUP\|-INT] PID` | Send signal to process |
| `env` | Show environment variables |
| `free` | Show memory/disk usage |
| `df` | Show filesystem usage |
| `clear` | Clear the screen |

## Filesystem

| Command | Description |
|---------|-------------|
| `mount` | List mounted filesystems |
| `mount DEVICE MOUNTPOINT` | Mount a device |
| `umount MOUNTPOINT` | Unmount a filesystem |
| `reboot` | Reboot the computer |
| `poweroff` | Shut down the computer |

## Network

| Command | Description |
|---------|-------------|
| `ifconfig [up\|down\|hostname NAME]` | Show/configure network interfaces |
| `ping [-c N] HOSTNAME_OR_ID` | Send ping packets to another computer |
| `wget URL [DEST]` | Download a file via HTTP |

## Package management (pacman)

| Command | Description |
|---------|-------------|
| `pacman -Sy` | Sync package databases |
| `pacman -Su` | Upgrade all packages |
| `pacman -Syu` | Sync + upgrade |
| `pacman -S NAME` | Install a package |
| `pacman -R NAME` | Remove a package |
| `pacman -Q` | List installed packages |
| `pacman -Qs QUERY` | Search installed packages |
| `pacman -Ss QUERY` | Search available packages |
| `pacman -Si NAME` | Show available package info |
| `pacman -Qi NAME` | Show installed package info |
| `pacman -Sc` | Clean package cache |
| `pacman -V` | Show pacman version |
| `pacman -h` | Show help |

## Service management (systemctl)

| Command | Description |
|---------|-------------|
| `systemctl start NAME` | Start a service |
| `systemctl stop NAME` | Stop a service |
| `systemctl restart NAME` | Restart a service |
| `systemctl status NAME` | Show service status |
| `systemctl enable NAME` | Enable service to start on boot |
| `systemctl disable NAME` | Disable service |
| `systemctl list-units` | List all units |
| `systemctl daemon-reload` | Reload unit files |
| `systemctl reboot` | Reboot via systemd |
| `systemctl poweroff` | Power off via systemd |

## Package sources

| Command | Description |
|---------|-------------|
| `pastebin get PASTE_ID DEST` | Download from pastebin.com |
| `pastebin run PASTE_ID [ARGS]` | Download and execute from pastebin |
| `git clone USER/REPO [DEST]` | Clone a GitHub repository |
| `git pull` | Pull updates from origin |
| `git status` | Show local changes |
| `pinestore search QUERY` | Search pinestore.cc |
| `pinestore install APP_ID` | Install app from pinestore.cc |
| `pinestore info APP_ID` | Show app info |
| `arch-update` | Update the OS (equivalent to `pacman -Syu`) |

## GUI applications (in /usr/bin)

| Application | Description |
|-------------|-------------|
| `editor [FILE]` | Text editor with Lua syntax highlighting |
| `browser [PATH]` | Text-mode file browser (TUI) |
| `gbrowse [PATH]` | Graphical file browser (uses paintutils) |
| `lua-repl` | Interactive Lua REPL |
| `sysmgr` | System Manager TUI (users, network, services) |
| `settings` | Settings app (BIOS, network, display) |
| `top` | Live process monitor |
| `neofetch` | System info display with ASCII art |
| `taskmgr` | Task Manager (TUI) |
| `calculator` | GUI calculator |
| `notes` | Notes/todo app |
| `player` | Audio player (notes, melodies, piano mode) |
| `paint [FILE]` | Pixel art editor |
| `monitor-app` | Monitor manager |
| `redstone-panel` | Redstone control panel GUI |

## Shell special syntax

| Syntax | Meaning |
|--------|---------|
| `cmd1 \| cmd2` | Pipe (basic implementation) |
| `cmd1 && cmd2` | Run cmd2 only if cmd1 succeeds |
| `cmd1 \|\| cmd2` | Run cmd2 only if cmd1 fails |
| `cmd1 ; cmd2` | Run sequentially |
| `cmd &` | Run in background |
| `cmd > file` | Redirect stdout to file (overwrite) |
| `cmd >> file` | Redirect stdout to file (append) |
| `cmd < file` | Read stdin from file |
| `$VAR` or `${VAR}` | Variable expansion |
| `~/path` | Home directory expansion |
| `#` | Comment (to end of line) |

## Keyboard shortcuts (in shell)

| Key | Action |
|-----|--------|
| Up arrow | Previous command in history |
| Down arrow | Next command in history |
| Backspace | Delete char before cursor |
| Enter | Execute current line |
| Ctrl+T | Terminate current program (CC:Tweaked builtin) |
| Ctrl+C | Send SIGINT to foreground process |

## Editor keyboard shortcuts

When using `/usr/bin/editor.lua`:

| Key | Action |
|-----|--------|
| Ctrl+S | Save file |
| Ctrl+Q | Quit (without saving) |
| Ctrl+X | Quit (prompt to save if modified) |
| Ctrl+F | Find |
| Ctrl+G | Goto line |
| Ctrl+D | Delete current line |
| Ctrl+Z | Undo |
| Arrow keys | Move cursor |
| Page Up/Down | Scroll |
| Home/End | Move to start/end of line |

## BIOS keyboard shortcuts

During the BIOS POST screen (first 2 seconds of boot):

| Key | Action |
|-----|--------|
| F2 | Enter BIOS Setup |
| F12 | Open boot menu |

## Bootloader

The bootloader reads `/bootloader/entries/*.lua`. Each file returns:

```lua
return {
    name = "MyOS",
    kernel = "/path/to/kernel.lua",
    init = "/path/to/init.lua",
    description = "My custom OS",
    args = { ... }
}
```

To add a new OS to the boot menu, just drop a new `.lua` file in
`/bootloader/entries/` and reboot.

## Default files & directories

| Path | Description |
|------|-------------|
| `/etc/passwd` | User database |
| `/etc/group` | Group database |
| `/etc/shadow` | Password hashes |
| `/etc/fstab` | Filesystem mount table |
| `/etc/hostname` | Computer hostname |
| `/etc/issue` | Login banner |
| `/etc/motd` | Message of the day |
| `/etc/profile` | System-wide shell profile |
| `/etc/network.conf` | Network configuration |
| `/etc/os-release` | OS identification |
| `/etc/default-de` | Default desktop environment |
| `/etc/bios.conf` | BIOS configuration |
| `/etc/systemd/system/*.service` | Service unit files |
| `/var/log/boot.log` | Boot log |
| `/var/lib/pacman/` | Pacman databases |
| `/var/cache/pacman/pkg/` | Downloaded package cache |
| `/var/run/` | Runtime data (e.g., enabled services) |
| `/root/` | root user home directory |
| `/home/USER/` | Regular user home directories |
| `/mnt/diskX/` | Mounted disk drives |
| `/tmp/` | Temporary files |
