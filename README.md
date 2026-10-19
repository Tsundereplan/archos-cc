# ArchOS-CC

> An Arch Linux-inspired operating system for ComputerCraft: Tweaked,
> written in pure Lua.

```
   ___                     ____   ____  _  __
  /   | ______ __ ___     /  _/  / __ \/ |/ /
 / /| |/ __/ / // (_-<    / /   / /_/ /    /
/_/ |_|/_/  /_//_/___/   /___/  /____/_/|_/
```

ArchOS-CC brings the philosophy and feel of Arch Linux to the ComputerCraft:
Tweaked world. It boots through a BIOS, hands off to an open bootloader
(that can boot multiple OSes), and runs a cooperative kernel with a full
userland: shell, package manager (`pacman`), service manager (`systemd`),
multi-user system with passwords, virtual filesystem with mount points,
Plug-and-Play peripheral driver manager, and four desktop environments
(TTY, GNOME-like, Plasma-like, XFCE-like).

## Highlights

* **Open bootloader** — install multiple OSes side-by-side in
  `/bootloader/entries/`, switch between them with a boot menu.
* **BIOS** — press `F2` during POST to enter BIOS setup; `F12` for boot menu.
* **Cooperative kernel** — process manager, scheduler, syscalls, event bus,
  permission system.
* **Multi-user** — `/etc/passwd`, `/etc/group`, `/etc/shadow`, password
  hashing with multi-round FNV-1a (CC:Tweaked has no native crypto).
* **Pacman** — Arch-style package manager with sync/install/remove/upgrade,
  can pull from GitHub-hosted repos or `pinestore.cc`.
* **Systemd** — service manager supporting `start/stop/restart/enable/disable`
  and unit files in `/etc/systemd/system/`.
* **Plug-and-Play** — auto-detects and tracks peripherals (drives, monitors,
  modems, printers, speakers); fires events on attach/detach.
* **GitHub-native** — the installer downloads all OS files from a GitHub
  repo you control. Update by pushing commits and running `arch-update`.
* **pinestore.cc client** — search and install community apps directly.
* **Four desktop environments**:
  * **TTY** — text-only, Arch bare TTY look.
  * **GNOME-like** — clean graphical DE with activities overview.
  * **Plasma-like** — advanced DE with panel, KRunner, widgets, window
    decorations, dragging.
  * **XFCE-like** — lightweight panel + window manager.

## Requirements

* ComputerCraft: Tweaked 1.100+ (older versions may work but are untested).
* An **Advanced Computer** (color terminal). TTY mode also works on basic
  computers but most apps and DEs require color.
* HTTP API enabled in the server's `computercraft-server.toml` (or
  ComputerCraft.cfg) — `http.enabled = true` — required for installation
  and GitHub/pinestore access.
* A GitHub repository hosting the OS files (see
  [Installation](#installation)).

## Installation

The OS is installed via a single `installer.lua` that fetches all other
files from your GitHub repository.

### Quick install (recommended)

1. Create a public GitHub repo named `archos-cc` (or any name).
2. Upload all the files in this folder to the root of the repo.
3. Get the raw URL of `installer.lua` — it will look like:
   ```
   https://raw.githubusercontent.com/<your-username>/archos-cc/main/installer.lua
   ```
4. In an **Advanced Computer** in Minecraft, run:
   ```lua
   wget https://raw.githubusercontent.com/<your-username>/archos-cc/main/installer.lua /installer.lua
   installer <your-username> archos-cc main
   ```
5. The installer will:
   * Download every file in the manifest to your computer's disk.
   * Create the root user with a password you choose.
   * Set the default desktop environment.
   * Reboot into the bootloader.

### Alternative: pastebin

Upload `installer.lua` to pastebin.com, then on the computer:

```lua
pastebin run <paste_id> <your-username> archos-cc main
```

### First boot

* The bootloader shows the BIOS POST screen for 2 seconds.
* Press `F2` to enter BIOS setup.
* Press `F12` for the boot menu.
* After BIOS, the bootloader hands off to `/kernel/init.lua`, which runs
  `/sbin/init.lua` as PID 1.
* `init` mounts filesystems, brings up the network, starts services,
  and finally spawns the login prompt (or the chosen graphical DE).

## Project layout

```
archos-cc/
├── installer.lua            ← download-everything installer
├── startup.lua              ← CC:Tweaked entry point
├── bios/bios.lua            ← BIOS layer (POST, setup, boot menu)
├── bootloader/
│   ├── bootloader.lua       ← OS-agnostic bootloader
│   ├── default              ← default entry name
│   └── entries/
│       ├── archos.lua       ← ArchOS-CC entry
│       └── craftos.lua      ← vanilla CraftOS entry
├── kernel/
│   ├── init.lua             ← kernel main
│   ├── process.lua          ← process manager (coroutines)
│   ├── scheduler.lua        ← cooperative scheduler
│   ├── syscall.lua          ← Kernel.* syscall interface
│   ├── events.lua            ← event bus
│   └── permissions.lua      ← uid/gid/mode bits
├── lib/
│   ├── fs.lua               ← virtual filesystem + mount points
│   ├── users.lua            ← /etc/passwd + /etc/shadow
│   ├── crypto.lua           ← SHA-256, SHA-1, base64, RC4, XOR
│   ├── network.lua          ← modem + http + GitHub + pinestore
│   ├── drivers/             ← disk, monitor, modem, printer, speaker, pnp
│   └── arch/
│       ├── pacman.lua       ← Arch-style package manager
│       └── systemd.lua      ← service manager
├── bin/                     ← Unix-like commands (49 files)
├── sbin/                    ← system daemons + init
├── usr/bin/                 ← GUI apps (16 files: editor, browser, ...)
├── de/                      ← Desktop Environments (tty, gnome, plasma, xfce)
├── etc/                     ← configuration files
│   ├── passwd, group, shadow, fstab, hostname
│   ├── issue, motd, profile
│   ├── network.conf, os-release, default-de
│   ├── locale/en.lc
│   └── systemd/system/*.service
├── var/log/boot.log         ← boot log
├── var/lib/pacman/          ← pacman databases
├── docs/
│   ├── INSTALL.md
│   ├── ARCHITECTURE.md
│   ├── COMMANDS.md
│   └── DEVELOPMENT.md
├── README.md                ← this file
├── LICENSE                  ← MIT
└── .gitignore
```

## License

MIT. See [LICENSE](LICENSE).

## Contributing

Pull requests welcome! Read [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for
architecture notes and code style.
