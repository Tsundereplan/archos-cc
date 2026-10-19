# Installation Guide

This guide covers installing ArchOS-CC on a ComputerCraft: Tweaked
**Advanced Computer**.

## Prerequisites

### 1. ComputerCraft: Tweaked

Make sure CC:Tweaked is installed on your Minecraft server (Forge or Fabric).
Recommended version: 1.100+.

### 2. Enable HTTP API

Edit `computercraft-server.toml` (or `ComputerCraft.cfg` on older versions):

```toml
[http]
enabled = true
```

Without HTTP, the installer cannot download files. You can still install
from a disk image if you copy the files manually.

### 3. Build an Advanced Computer

You need:
* 1x Advanced Computer (gold-plated, supports color).
* Optional but recommended: 1x Wired Modem + Networking Cable for rednet.
* Optional: 1x Monitor for graphical DE (large enough, e.g. 4 wide x 3 tall).
* Optional: 1x Disk Drive for installing from / saving to floppy disks.

### 4. Create the GitHub repository

1. Go to https://github.com/new
2. Repository name: `archos-cc` (or any name).
3. Visibility: **Public** (so the installer can fetch via `raw.githubusercontent.com`).
4. Initialize with README (optional).
5. Upload all the files from this `archos-cc/` folder to the root of the repo.
   You can drag-and-drop the entire folder structure on the GitHub web UI.

Take note of your **GitHub username** and the **branch name** (default: `main`).

## Installing

### Method A: From GitHub (recommended)

Place the Advanced Computer and right-click to open the terminal. Then:

```lua
wget https://raw.githubusercontent.com/<your-username>/archos-cc/main/installer.lua /installer.lua
installer <your-username> archos-cc main
```

The installer will:
1. Download all ~120 files from your GitHub repo.
2. Show progress for each file (OK / FAIL).
3. Run post-install hooks (create `/var/log`, `/home`, `/tmp`).
4. Set a root password (or skip if you want to do it later with `passwd`).
5. Ask you to pick the default desktop environment.
6. Reboot.

### Method B: From pastebin

Upload `installer.lua` to https://pastebin.com, then:

```lua
pastebin run <paste_id> <your-username> archos-cc main
```

### Method C: From disk (offline)

If your server doesn't allow HTTP, you can copy the files onto a floppy disk
or directly into the computer's save folder:

1. Find the world's `computer/<ID>` folder (e.g. `<world>/computer/1/`).
2. Copy all the files from this `archos-cc/` folder into that directory,
   preserving the subdirectory structure.
3. Make sure `startup.lua` is at the root level.
4. Boot the computer.

## First boot

After the installer reboots the computer:

1. **BIOS POST screen** — shows for 2 seconds. Press:
   * `F2` to enter BIOS Setup (configure boot delay, PnP, network, etc.)
   * `F12` to enter the boot menu (if you have multiple OSes installed).

2. **Bootloader** — automatically selects the default boot entry (`archos`).

3. **Kernel init** — `/kernel/init.lua` loads kernel modules and libraries.

4. **`/sbin/init.lua`** mounts filesystems, brings up network, starts services.

5. **Login** — if you set a root password, you'll see the login prompt:
   ```
   login: root
   Password: ********
   ```
   If you skipped the password, you'll be auto-logged in as `root`.

6. **Desktop Environment** — based on your installer choice:
   * `tty` → text-mode TTY login shell.
   * `gnome` / `plasma` / `xfce` → graphical DE launches after login.

## Post-install configuration

### Set a root password (if skipped)

```bash
passwd
```

### Create a regular user

```bash
useradd -m alice
passwd alice
```

### Add user to the wheel group (sudo access)

Edit `/etc/group` and add `alice` to the `wheel` line:

```
wheel:x:10:alice
```

Now `alice` can use `sudo`:

```bash
su - alice
sudo ls /root
```

### Switch desktop environment

```bash
# Edit /etc/default-de and put one of: tty, gnome, plasma, xfce
echo "plasma" > /etc/default-de
reboot
```

### Change hostname

```bash
hostname my-awesome-pc
# or via Network library:
ifconfig hostname my-awesome-pc
```

### Set up GitHub package repo

If you want to install community packages via `pacman`:

1. Create another GitHub repo (e.g. `archos-cc-repo`) with two files:
   * `core.db` — line-separated package list:
     ```
     mypackage|1.0.0|Does cool stuff|https://raw.githubusercontent.com/you/archos-cc-repo/main/mypackage.lua|
     ```
   * `mypackage.lua` — the package installer script.

2. Edit `/lib/arch/pacman.lua` and update the `config.repos[1].url` field
   to point to your repo.

3. Run `pacman -Sy` to sync, then `pacman -S mypackage` to install.

### Use pinestore.cc

```bash
pinestore search turtle
pinestore install <appId>
```

## Troubleshooting

### "command not found" for everything

Check that `/bin/sh.lua` exists. If not, re-run the installer.

### No network (modem not detected)

* Verify the modem is attached to a side of the computer.
* Open BIOS setup (`F2` during boot) and ensure "Network init" is enabled.
* Check `/var/log/boot.log` for `[modem]` entries.

### Login fails with "user does not exist"

The `/etc/passwd` file may be corrupted. Run from the boot menu → `craftos`
entry to get a vanilla shell, then:

```lua
local f = fs.open("/etc/passwd", "w")
f.write("root:x:0:0:root:/root:/bin/sh.lua\n")
f.close()
```

### Kernel panic

The kernel panics if init crashes or a critical file is missing. Boot into
CraftOS via the boot menu (`F12` during POST) to diagnose.

## Updating the OS

Once installed, you can update via:

```bash
arch-update
```

This is equivalent to `pacman -Syu` — syncs the database and upgrades all
packages.
