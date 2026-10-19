# ArchOS-CC — Quick Start

## What's in this archive

```
archos-cc/
├── installer.lua          ← download-and-install script
├── startup.lua             ← CC:Tweaked boot entry
├── bios/bios.lua           ← BIOS (POST + F2 setup + F12 boot menu)
├── bootloader/             ← open bootloader with boot entries
│   ├── bootloader.lua
│   ├── default             ← which entry boots by default
│   └── entries/
│       ├── archos.lua      ← ArchOS-CC entry
│       └── craftos.lua     ← CraftOS 1.9 vanilla shell entry ★ NEW
├── kernel/                 ← kernel (init, process, scheduler, syscall, ...)
│   └── craftos-shim.lua    ← launches the native CraftOS shell ★ NEW
├── lib/                    ← VFS, users, crypto, network + drivers + pacman + systemd
├── bin/                    ← 50 Unix-like commands (sh, ls, pacman, systemctl, ...)
├── sbin/                   ← system daemons (init, fsck, mkfs, networkd, mountd)
├── usr/bin/                ← 15 GUI applications (editor, browser, paint, calculator, ...)
├── de/                     ← 4 desktop environments (tty, gnome, plasma, xfce)
├── etc/                    ← config files (passwd, fstab, hostname, os-release, ...)
├── docs/                   ← full documentation
├── var/                    ← runtime (logs, pacman DBs, cache)
├── README.md
├── LICENSE                 ← MIT
├── MANIFEST                ← list of all files
└── .gitignore
```

## Three ways to install

### 1. From your own GitHub repo (recommended)

1. Unzip this archive on your computer.
2. Create a public GitHub repo (e.g. `archos-cc`).
3. Upload all files to the root of the repo (see `docs/GITHUB_SETUP.md`).
4. In ComputerCraft: Tweaked on an **Advanced Computer**, run:
   ```lua
   wget https://raw.githubusercontent.com/<your-username>/archos-cc/main/installer.lua /installer.lua
   installer <your-username> archos-cc main
   ```

### 2. From pastebin

Upload `installer.lua` to https://pastebin.com/, then:
```lua
pastebin run <paste_id> <your-username> archos-cc main
```

### 3. From disk (offline)

1. Find your world's `computer/<ID>/` folder.
2. Copy all files from this `archos-cc/` folder into it, preserving subdirs.
3. Reboot the computer.

## Boot menu

After BIOS POST (2 seconds), the bootloader scans `/bootloader/entries/`.
You'll see at least two entries:

```
==========================================
       ArchOS-CC Boot Menu
==========================================

  1. archos    Arch Linux style OS for CC:Tweaked
  2. craftos   Boot into the standard CraftOS 1.9 shell (no ArchOS)

  Select entry (1-2):
```

Pick `craftos` to boot into the **vanilla CraftOS 1.9 shell** —
no ArchOS-CC process manager, no VFS, no users, no PnP. Just the
plain CC:Tweaked shell as it ships.

Pick `archos` for the full ArchOS-CC experience (TTY / GNOME / Plasma / XFCE).

You can also press **F12 during BIOS POST** to force the boot menu, or
**F2 to enter BIOS setup**.

## Switching the default boot entry

Edit `/bootloader/default` (a single line with the entry name):

```bash
echo "craftos" > /bootloader/default
reboot
```

## Adding your own OS to the boot menu

Just drop a new `.lua` file in `/bootloader/entries/`:

```lua
-- /bootloader/entries/myos.lua
return {
    name        = "My Custom OS",
    kernel      = "/path/to/my/kernel.lua",
    description = "Description shown in the boot menu",
    args        = {}
}
```

It will appear automatically the next time you boot.

## Switching desktop environments (inside ArchOS-CC)

```bash
echo plasma > /etc/default-de    # or: tty, gnome, xfce
reboot
```

## Useful first commands after install

```bash
passwd                          # set root password if you skipped it
useradd -m alice                # create a regular user
passwd alice                    # set alice's password
neofetch                        # show system info
pacman -Sy                      # sync package database
pacman -Ss editor               # search for packages
ls /                            # see filesystem root
systemctl list-units            # see running services
```

## Documentation

| File | What's inside |
|------|---------------|
| `docs/INSTALL.md` | Detailed install & troubleshooting |
| `docs/ARCHITECTURE.md` | How the OS is layered (BIOS → bootloader → kernel → init → DE) |
| `docs/COMMANDS.md` | Reference for every command |
| `docs/DEVELOPMENT.md` | How to add commands, drivers, services, DEs |
| `docs/GITHUB_SETUP.md` | Step-by-step git upload to your own repo |

## Requirements

- ComputerCraft: Tweaked 1.100+
- **Advanced Computer** (color terminal) for GUI DEs
- HTTP API enabled (`http.enabled = true` in `computercraft-server.toml`)
- A GitHub repo (public) hosting these files, OR a floppy disk with the files

## License

MIT — see `LICENSE`.
