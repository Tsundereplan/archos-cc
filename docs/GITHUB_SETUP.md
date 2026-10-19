# How to upload ArchOS-CC to your GitHub repository

This guide walks you through pushing the ArchOS-CC source to a new GitHub
repo so that the installer can download it.

## Step 1: Create the repo on GitHub

1. Go to https://github.com/new
2. **Repository name**: `archos-cc` (recommended) or any name you like.
3. **Description**: "Arch Linux style OS for ComputerCraft: Tweaked"
4. **Visibility**: **Public** (required so the installer can fetch the files
   via `raw.githubusercontent.com`).
5. **Initialize this repository with:**
   * Leave all checkboxes **unchecked**. (We're going to push an existing
     folder, not create a README from scratch.)
6. Click **Create repository**.

GitHub will give you a URL like:
```
https://github.com/<your-username>/archos-cc
```

## Step 2: Initialize git in the project folder

Open a terminal on your computer (NOT in Minecraft), navigate to the
folder where ArchOS-CC is, and run:

```bash
cd /path/to/archos-cc

# Initialize git
git init

# Add all files
git add .

# Make your first commit
git commit -m "Initial commit: ArchOS-CC 1.0.0 (Quartz)

- BIOS, open bootloader, kernel (process/scheduler/syscalls/events/perms)
- Multi-user system with /etc/passwd, /etc/shadow, password hashing
- Virtual filesystem with mount points, permission checks
- Plug-and-Play driver manager (disk, monitor, modem, printer, speaker)
- pacman package manager + systemd service manager
- 50 bin/ Unix-like commands
- 15 usr/bin GUI applications (editor, browser, paint, calculator, etc.)
- 4 desktop environments: TTY, GNOME-like, Plasma-like, XFCE-like
- GitHub installer + pinestore.cc client"

# Set the branch name to 'main'
git branch -M main

# Add your GitHub repo as the remote origin
git remote add origin https://github.com/<your-username>/archos-cc.git

# Push everything to GitHub
git push -u origin main
```

Replace `<your-username>` with your actual GitHub username.

If you have **SSH** set up with GitHub instead of HTTPS:

```bash
git remote add origin git@github.com:<your-username>/archos-cc.git
git push -u origin main
```

## Step 3: Verify the upload

Go to your repo on GitHub:
```
https://github.com/<your-username>/archos-cc
```

You should see all the files and folders:
- `installer.lua`, `startup.lua`, `README.md`, `LICENSE`
- `bios/`, `bootloader/`, `kernel/`, `lib/`, `bin/`, `sbin/`, `usr/`,
  `de/`, `etc/`, `docs/`, `var/`

Verify the installer is reachable by fetching this URL in your browser:

```
https://raw.githubusercontent.com/<your-username>/archos-cc/main/installer.lua
```

You should see the Lua source code of `installer.lua`.

## Step 4: Install on a ComputerCraft computer

In Minecraft, right-click your **Advanced Computer** and run:

```lua
wget https://raw.githubusercontent.com/<your-username>/archos-cc/main/installer.lua /installer.lua
installer <your-username> archos-cc main
```

The installer will download all ~120 files, set up the root password, pick
a default desktop environment, and reboot into ArchOS-CC.

## Step 5: Updating the OS

When you change files in your repo:

```bash
# Locally
git add .
git commit -m "your change description"
git push
```

On the ComputerCraft computer, run:

```bash
arch-update
```

This re-syncs the package database and upgrades any changed packages.

Or, to re-run the full installer:

```bash
installer <your-username> archos-cc main
```

## Common issues

### "Permission denied (publickey)"

Your SSH key isn't set up. Either:
* Set up SSH keys (see https://docs.github.com/en/authentication/connecting-to-github-with-ssh), or
* Use HTTPS instead of SSH (the URL with `https://github.com/...`).

### "Repository not found" when installer runs

Make sure the repo is **public**. Private repos require authentication
which `wget`/HTTP can't do in CC:Tweaked.

### Installer fails with "download failed" for some files

Check that the file actually exists in the repo at the expected path.
The installer constructs URLs like:

```
https://raw.githubusercontent.com/<user>/<repo>/<branch>/<path>
```

Make sure all paths in the MANIFEST in `installer.lua` match the actual
file paths in your repo.

### GitHub URL-encodes spaces

If you have files with spaces in the name, GitHub's raw URL will
percent-encode them. The installer handles this for you (line `url:gsub("
", "%%20")`), but if you add new files with unusual characters, test the
URL manually first.

## Alternative: GitHub Desktop

If you don't want to use the command line, you can use GitHub Desktop:

1. Download from https://desktop.github.com/
2. Sign in with your GitHub account.
3. Click "Add an Existing Repository from your Hard Drive".
4. Select the `archos-cc/` folder.
5. Click "Publish repository".
6. Make sure "Keep this code private" is **unchecked** (we need public).

## Alternative: Upload via web UI

For a one-time upload without git:

1. Go to https://github.com/<your-username>/archos-cc/upload/main
2. Drag the entire archos-cc folder contents into the upload area.
3. Add a commit message.
4. Click "Commit changes".

Note: GitHub's web UI doesn't support uploading empty folders. The
`.gitkeep` files we created ensure all directories are preserved.

## Verifying everything works

After installing in Minecraft:

1. **Boot menu**: press `F12` during BIOS POST to see the boot menu.
2. **BIOS setup**: press `F2` during BIOS POST.
3. **TTY mode**: login, run `ls /`, `pacman -Q`, `neofetch`.
4. **Graphical mode**: `echo plasma > /etc/default-de` then `reboot`.
5. **Run apps**: try `editor`, `browser`, `top`, `paint`, `calculator`.

If anything breaks, check `/var/log/boot.log` for diagnostics.

## Keeping the OS up to date for users

If you want to share your OS with others, you can:

1. Make the repo public (already done in step 1).
2. Tell users to install with:
   ```lua
   wget https://raw.githubusercontent.com/<your-username>/archos-cc/main/installer.lua /installer.lua
   installer <your-username> archos-cc main
   ```
3. They'll get the latest version on every `arch-update`.

## Forking and modifying

If someone forks your repo, they need to:

1. Update `installer.lua`'s default `GITHUB_USER` (or pass their username
   as the first arg).
2. Update `lib/arch/pacman.lua`'s `config.repos` to point to their package
   repo.
3. Update `bin/arch-update.lua`'s `GITHUB_USER` constant.
4. Update `etc/os-release`'s `HOME_URL` and `DOCUMENTATION_URL`.
5. Update `README.md` and `docs/INSTALL.md` with their URLs.

That's it! Have fun with ArchOS-CC.
