# Installation

The [README](../README.md#quick-installation) covers the quick path. This
page covers each platform in detail.

Always preview first:

```sh
./install.sh --dry-run
```

## macOS

1. Install [Homebrew](https://brew.sh) if it is missing. The installer does
   not run the Homebrew install script for you.
2. Clone and install:

   ```sh
   git clone https://github.com/gweilo852/dotfiles.git ~/dotfiles
   cd ~/dotfiles
   ./install.sh
   ```

3. The installer runs `brew bundle` with `platforms/macos/Brewfile`
   (only missing packages, no upgrades) and installs the WezTerm cask only
   when `WezTerm.app` is not already in `/Applications`.
4. Open a new WezTerm window, or run `exec zsh`.
5. Review `~/.zshrc.local`. It holds the content of your old `~/.zshrc`.
   Lines that start with `: # [dotfiles]` are disabled because the managed
   configuration now does the same thing. Delete them when you are
   satisfied.

## Linux

```sh
sudo apt-get install -y git curl     # or dnf, pacman, zypper, apk
git clone https://github.com/gweilo852/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh --dry-run
./install.sh
```

The installer asks the package manager for each missing tool in
`platforms/linux/packages.tsv`. On apt it checks that a package exists
before it installs it. Tools that the distribution does not package (for
example `starship` or `eza` on Ubuntu 22.04) are listed at the end. To
install them without root:

```sh
./install.sh --no-packages --release-binaries
```

This downloads the pinned archives in `platforms/linux/release-binaries.tsv`
for your CPU (x86_64 or aarch64), checks each SHA-256 value, and installs
the binaries into `~/.local/bin`. Nothing downloaded is run during the
installation.

To make zsh the login shell: `chsh -s "$(command -v zsh)"`. If you stay
with bash, the block in `~/.bashrc` gives you the same prompt and tools.

## WSL (the-beast)

Inside WSL, follow the Linux steps and add `--windows-wezterm`:

```sh
./install.sh --dry-run --windows-wezterm
./install.sh --windows-wezterm
```

`--windows-wezterm` finds `%USERPROFILE%` with `cmd.exe` and copies
`config/wezterm/wezterm.lua` to `%USERPROFILE%\.wezterm.lua`. An existing
file there is backed up first. WezTerm on Windows reads `~/.wezterm.lua`
before `~/.config/wezterm/wezterm.lua`; the installer warns when both exist.

On the Windows side:

1. `winget install wez.wezterm`
2. Install "CaskaydiaMono Nerd Font" (from nerdfonts.com, CascadiaMono.zip)
   with "Install for all users".
3. Start WezTerm. On Windows the config opens the first WSL distribution
   in your Linux home directory. To start PowerShell instead, see
   `config/wezterm/wezterm_local.example.lua`.

After you change `wezterm.lua`, run `./install.sh --windows-wezterm` again
to copy it.

## Unraid

Unraid is not a conventional Linux system:

- `/` and `/root` are in RAM. Unraid rebuilds them at every boot.
- `/boot` is the USB flash drive (FAT32): no symlinks, no executables.
- There is no supported package manager, and usually no zsh.

Unraid mode is therefore minimal and must be selected explicitly. It:

- requires `--unraid` (without it, the installer stops on Unraid);
- requires the repository on persistent storage under `/mnt`;
- installs no packages;
- links the Starship and tmux configuration into `/root` and adds the bash
  block to `/root/.bashrc` (and to `/root/.bash_profile` when it does not
  already source `.bashrc`);
- keeps its manifest and backups in `<repo>/.state` and `<repo>/.backups`;
- never writes to `/boot` and never changes `/boot/config/go`.

### Procedure

1. Open a terminal on the server (SSH as root, or the web terminal).
2. Clone onto persistent storage. A share on a pool (for example
   `appdata`) is best:

   ```sh
   cd /mnt/user/appdata
   git clone https://github.com/gweilo852/dotfiles.git
   cd dotfiles
   ```

3. Preview:

   ```sh
   ./scripts/bootstrap-unraid.sh --dry-run --release-binaries
   ```

   The preflight shows the Unraid version, confirms the location and lists
   missing tools. The dry run lists every link and block.

4. Install. `--release-binaries` puts starship, zoxide, fzf, eza, bat, delta
   and duf into `<repo>/.local/bin` on persistent storage:

   ```sh
   ./scripts/bootstrap-unraid.sh --release-binaries
   ```

5. Start a new shell: `exec bash -l`.
6. Check: `./scripts/doctor.sh`.

### After a reboot

The links in `/root` are gone after a reboot; the repository and the
binaries remain. To relink by hand:

```sh
/mnt/user/appdata/dotfiles/install.sh --unraid --yes
```

To relink automatically, you can use the User Scripts plugin. This is an
explicit choice for you to make; the installer does not do it:

1. Install the "User Scripts" plugin from Community Applications.
2. Add a new script and paste the content of
   `platforms/unraid/user-script.sh`. Check `DOTFILES_DIR`.
3. Set the schedule to "At Startup of Array".

Do not put the dotfiles in `/boot/config/go` unless you understand the boot
sequence; the array (and so `/mnt`) is not mounted when `go` runs.

### Removal

```sh
cd /mnt/user/appdata/dotfiles
./uninstall.sh --dry-run
./uninstall.sh
```

Then delete the directory if you want. A reboot also removes every link.

## What the installer never does

- Run a script downloaded from the internet.
- Overwrite a file without a backup and a message.
- Delete `~/.oh-my-zsh`, `~/.ssh`, kubeconfig files or shell history.
- Change the login shell.
- Write to `/boot` on Unraid.
