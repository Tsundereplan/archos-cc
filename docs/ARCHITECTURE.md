# Architecture

This document describes the internal architecture of ArchOS-CC.

## Boot sequence

```
+-------------------+   +------------------+   +------------------+
|  CC:Tweaked       |   |                  |   |                  |
|  /startup.lua  -->|-->|  /bios/bios.lua  |-->|  bootloader.lua  |
|  (auto-run)       |   |  (POST + setup)   |   |  (entries)       |
+-------------------+   +------------------+   +--------+---------+
                                                        |
                                                        v
+-------------------+   +------------------+   +------------------+
|  /sbin/init.lua   |<--|  /kernel/init.lua |<--|  loads entry    |
|  (PID 1: mount,   |   |  (sets up Kernel  |   |  (e.g. archos)  |
|   network, login) |   |   Process, FS,   |   +------------------+
+-------------------+   |   Permissions)    |
        |               +------------------+
        v
+-------------------+
|  /bin/login.lua   |
|  (auth + shell)   |
+-------------------+
        |
        v
+-------------------+
|  /de/<de>.lua     |  (TTY / GNOME / Plasma / XFCE)
|  Desktop Env      |
+-------------------+
```

## Layers

### Layer 1: BIOS

`bios/bios.lua` runs first, called from `startup.lua`.

* Loads BIOS config from `/etc/bios.conf`.
* Performs POST (Power-On Self-Test): checks critical files, disk space.
* Detects peripherals (`BIOS.scanPeripherals`).
* Initializes PnP drivers.
* Shows the splash screen with hardware info.
* Listens for `F2` (BIOS Setup) or `F12` (Boot Menu) during the splash delay.

### Layer 2: Bootloader

`bootloader/bootloader.lua` is OS-agnostic.

* Scans `/bootloader/entries/` for `.lua` files.
* Each entry file returns a table: `{ name, kernel, init, description, args }`.
* Shows the boot menu if multiple entries exist.
* Loads the chosen entry's kernel file via `dofile()`.
* The kernel can return either a function or a table with `.run()`.

### Layer 3: Kernel

`kernel/init.lua` is the ArchOS-CC kernel.

* Loads kernel modules: `process`, `scheduler`, `syscall`, `events`, `permissions`.
* Loads core libraries: `fs`, `users`, `crypto`, `network`.
* Loads drivers via `lib/drivers/*.lua`.
* Loads arch subsystem: `pacman`, `systemd`.
* Creates `/proc`, `/dev`, `/tmp`, `/var/log` etc.
* Spawns PID 1 = `init` process running `/sbin/init.lua`.
* Enters the scheduler main loop.

### Layer 4: Init (PID 1)

`sbin/init.lua` is user-space init, equivalent to systemd.

* Mounts filesystems from `/etc/fstab`.
* Brings up the network (`Network.init()`).
* Starts enabled services (via `Systemd.start(name)`).
* Decides the desktop environment from `/etc/default-de`.
* Spawns `/de/<de>.lua` (or `/bin/login.lua` if `tty`).

### Layer 5: Userland

Userland consists of:

* `/bin/sh.lua` — bash-like shell (the main TTY interface).
* `/bin/*` — Unix-like commands (`ls`, `cat`, `cp`, `pacman`, `systemctl`, ...).
* `/sbin/*` — system daemons (`networkd`, `mountd`).
* `/usr/bin/*` — GUI applications (`editor`, `browser`, `top`, `paint`, ...).
* `/de/*` — desktop environments.

## Process model

ArchOS-CC uses **cooperative multitasking** based on Lua coroutines.

### Process table

Each process is a `Process` object with:

* `pid` — unique numeric ID
* `ppid` — parent PID
* `uid` / `gid` — owner
* `user` — username string
* `cwd` — current working directory
* `env` — environment table (PATH, HOME, USER, ...)
* `argv` — command-line arguments
* `coro` — the underlying Lua coroutine
* `status` — `ready`, `running`, `waiting`, `sleeping`, `dead`
* `exitCode` — set on death
* `window` — optional `term.redirect` target for this process's I/O
* `children` — list of child PIDs
* `signals` — queued signals
* `cpuTime` — accumulated execution time

### Scheduler

`kernel/scheduler.lua` runs the main loop:

1. **Tick** — resume all `ready` processes once.
2. **Wake sleepers** — check `proc.sleepUntil` against `os.clock()`.
3. **Pull event** — `os.pullEventRaw()` with a 50ms tick timer.
4. **Dispatch event** — to all processes whose `waitFor` filter matches.
5. **Repeat**.

PID 1 (`init`) is special: if it dies, the kernel panics and halts.

### Signals

Processes can receive signals via `Process.signal(pid, sig)`:

| Signal | Code | Behavior                                  |
|--------|------|-------------------------------------------|
| TERM   | 1    | Request termination (catchable)           |
| KILL   | 2    | Forceful kill (uncatchable, immediate)     |
| INT    | 3    | Ctrl+C equivalent                          |
| HUP    | 4    | Hangup (parent died)                        |
| STOP   | 5    | Pause (not yet implemented)                |
| CONT   | 6    | Resume from stop (not yet implemented)    |

## Filesystem layer

`lib/fs.lua` wraps the native `fs` API with:

### Virtual paths

Every path is normalized via `FS.normalize()`:
* Resolves `.` and `..`.
* Makes absolute relative to current process's `cwd`.
* Removes duplicate `/`.

### Mount points

Mount table: `path -> { source, type, options }`.

* `/` is always mounted to the CC root.
* Disk drives can be mounted at `/mnt/diskX` (auto-mounted by the disk driver).
* Custom mounts can be added via `FS.mount(path, source, opts)` or the `mount`
  command.

### Permission checks

When `lib/fs.lua` opens a file, it asks `kernel/permissions.lua` whether the
current uid/gid has `r`/`w`/`x` permission on the file. If not, the open
fails with `permission denied`.

Root (uid 0) bypasses all checks.

## Library layer

### `lib/fs.lua` — Virtual filesystem

`FS.*` provides: `normalize`, `resolve`, `exists`, `isDir`, `open`, `list`,
`makeDir`, `delete`, `move`, `copy`, `mount`, `umount`, `mounts`, `walk`,
`tree`, `readFile`, `writeFile`, `appendFile`.

### `lib/users.lua` — User database

`Users.*` provides: `load`, `save`, `addUser`, `delUser`, `getUser`,
`listUsers`, `addGroup`, `checkPassword`, `hashPassword`, `authenticate`.

Password hashing: 1000-round FNV-1a (salted with `os.time + computerID`).
Not cryptographically secure, but adequate for OS demo.

### `lib/crypto.lua` — Crypto helpers

* `Crypto.sha256(msg)` — full SHA-256 implementation (returns hex string).
* `Crypto.sha1(msg)` — SHA-1 (legacy).
* `Crypto.hmacSha256(key, msg)` — HMAC-SHA256.
* `Crypto.fnv1a(data)` — fast FNV-1a 32-bit hash.
* `Crypto.base64Encode(data)` / `Crypto.base64Decode(data)`.
* `Crypto.xorCipher(data, key)` — XOR cipher (symmetric).
* `Crypto.rc4(key, data)` — RC4 stream cipher.
* `Crypto.random(max)` — pseudo-random integer 1..max.

### `lib/network.lua` — Network stack

`Network.*` provides:
* Modem discovery and channel management.
* `send(targetID, msg)`, `broadcast(type, data)`, `receive(timeout, filter)`.
* DNS-like hostname lookup via `lookup(hostname)`.
* `ping(targetID)` returns round-trip time.
* HTTP wrappers: `httpGet`, `httpPost`, `httpRequest`.
* GitHub raw file fetcher: `fetchGitHubRaw(user, repo, branch, path)`.
* pinestore.cc client: `pinestoreSearch(query)`, `pinestoreInstall(appId)`.

## Drivers

Each driver registers itself with the PnP manager (`lib/drivers/pnp.lua`)
and gets callbacks on attach/detach events.

| Driver file          | Peripheral  | Notes                                    |
|----------------------|-------------|------------------------------------------|
| `lib/drivers/disk.lua`    | `drive`    | Auto-mount on insert; auto-unmount on eject |
| `lib/drivers/monitor.lua` | `monitor`  | Tracks sizes, types, resize events       |
| `lib/drivers/modem.lua`   | `modem`    | Wired/wireless, channel management        |
| `lib/drivers/printer.lua` | `printer`  | Queues print jobs, multi-page             |
| `lib/drivers/speaker.lua` | `speaker`  | Notes, sounds, DFPWM audio               |

## Arch subsystem

### Pacman (`lib/arch/pacman.lua`)

Arch-style package manager. Reads/writes:

* `/var/lib/pacman/local/<name>-<ver>/desc` — package metadata
* `/var/lib/pacman/local/<name>-<ver>/files` — installed file list
* `/var/lib/pacman/sync/<repo>.db` — available package list
* `/var/cache/pacman/pkg/` — downloaded packages

CLI: `/bin/pacman.lua` supports `-S`, `-R`, `-Q`, `-Ss`, `-Sy`, `-Su`, `-Syu`,
`-Sc`, `-V`, `-h`.

### Systemd (`lib/arch/systemd.lua`)

Service manager. Reads unit files from `/etc/systemd/system/<name>.service`:

```ini
[Unit]
Description=Network Daemon
After=mountd.service

[Service]
Type=simple
ExecStart=/sbin/networkd.lua
Restart=on-failure
User=root

[Install]
WantedBy=multi-user.target
```

CLI: `/bin/systemctl.lua` supports `start`, `stop`, `restart`, `status`,
`enable`, `disable`, `list-units`, `daemon-reload`, `reboot`, `poweroff`.

## Permissions

`kernel/permissions.lua` tracks:

* Per-path owner (uid), group (gid), and mode bits (octal like 755).
* Mode bits split into owner/group/other, each with rwx.
* Root (uid 0) bypasses all checks.

Permission metadata is stored in `/var/db/permissions/` (one file per path).
Common paths (`/`, `/bin`, `/etc`, `/home`) are cached in memory on first
load.

## Desktop environments

| DE       | File         | Look & feel                                            |
|----------|--------------|--------------------------------------------------------|
| TTY      | `de/tty.lua` | Bare Arch Linux TTY look; no graphics                  |
| GNOME    | `de/gnome.lua` | Top bar, activities overview, simple windows          |
| Plasma   | `de/plasma.lua` | Bottom panel, KRunner, widgets, window drag/resize   |
| XFCE     | `de/xfce.lua` | Lightweight panel + draggable windows                  |

Each DE runs `/bin/login.lua` first to authenticate, then takes over the
screen with its own event loop.

## Event bus

`kernel/events.lua` provides pub-sub for system events:

```lua
Events.subscribe("archos_device_attach", function(side, ptype)
    print("Device attached:", side, ptype)
end)
Events.dispatch("archos_custom_event", data1, data2)
```

Pre-defined event types (in `Events.TYPES`):

* `archos_device_attach` / `archos_device_detach`
* `archos_disk_insert` / `archos_disk_eject`
* `archos_fs_mount` / `archos_fs_umount`
* `archos_user_login` / `archos_user_logout`
* `archos_service_start` / `archos_service_stop`
* `archos_pkg_install` / `archos_pkg_remove`
* `archos_shutdown` / `archos_reboot`

## IPC (inter-process communication)

Processes communicate via:

1. **Events** — via `Kernel.sendEvent(event)` (broadcasts to all
   listeners).
2. **Files** — write to `/var/run/<name>` and read from another process.
3. **Signals** — `Kernel.signal(pid, sig)` to deliver signals.
4. **Pipes** — (planned, not yet implemented)

## Memory & disk

* Computer disk space is finite (varies by CC:Tweaked config, typically 1MB+
  per computer).
* The OS itself is ~150 KB. Plenty of room for user files and packages.
* No swap or virtual memory — if you run out of disk, you get errors.
* `free` and `df` commands show disk usage; `top` shows process CPU usage.

## Lua version

CC:Tweaked uses Cobalt, which is Lua 5.1 + some 5.2/5.3 features. The OS
code targets 5.1 syntax for compatibility:

* Use `string.format`, `table.unpack` (not 5.3's `table.unpack` always).
* Use `ipairs` for arrays, `pairs` for maps.
* No bitwise operators (`&`, `|`, `~`, `<<`, `>>`) — use `bit32` API or
  arithmetic equivalents.
* Use `:match`, `:gmatch`, `:gsub` instead of regex.
