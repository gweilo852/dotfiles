# dotfiles

A portable, low-glare terminal environment for macOS, Windows 11 with WSL,
Linux and Unraid. One repository gives every machine the same font, colours,
prompt, shell behaviour and command-line tools.

```text
╭─  ~/dotfiles  main !2 ⎈ kafka-emea-tst 󰔟 4s
╰─ ❯ ll --git
drwxr-xr-x  -  me 26 Oct 11:08 -- config
drwxr-xr-x  -  me 26 Oct 11:08 -- docs
.rwxr-xr-x 7.0k me 26 Oct 11:14 -M install.sh
.rw-r--r-- 9.1k me 26 Oct 11:30 -M README.md
```

The prompt shows the OS, directory, Git branch and status, the Kubernetes
context (red for production, yellow for staging, blue for testing, green for
sandbox), and how long the last slow command took. The second line turns red
when the last command failed.

## Contents

- [Features](#features)
- [Supported platforms](#supported-platforms)
- [Prerequisites](#prerequisites)
- [Quick installation](#quick-installation)
- [Manual installation](#manual-installation)
- [Everyday use](#everyday-use)
- [Keyboard shortcuts](#keyboard-shortcuts)
- [Low-glare colours and fonts](#low-glare-colours-and-fonts)
- [Updating](#updating)
- [Uninstallation](#uninstallation)
- [Customization](#customization)
- [Troubleshooting](#troubleshooting)
- [Security](#security)
- [Repository layout](#repository-layout)

## Features

- **WezTerm**: CaskaydiaMono Nerd Font Mono, DemiBold, 13.5 pt, ligatures,
  Catppuccin Macchiato with muted text, opaque background, steady cursor,
  comfortable padding and a minimal tab bar. One file for macOS and Windows.
- **Starship**: a two-line prompt with OS icon, directory, Git, Kubernetes
  context and command duration, in muted Catppuccin Macchiato colours.
  Kubernetes context names are shortened for display only, and every
  production cluster keeps a distinct name.
- **Native zsh**: no Oh My Zsh. Completion, history, autosuggestions, syntax
  highlighting, zoxide and fzf, each loaded exactly once. Generated
  completions are cached so a new shell starts quickly.
- **bash** on Linux, WSL and Unraid gets the same prompt, aliases and tools,
  and the distribution's own `~/.bashrc` stays in place.
- **Modern tools** with fallbacks: eza, bat, delta, duf, fzf, zoxide, tmux.
  Every alias falls back to the standard command when a tool is missing.
- **Safe installer**: dry run, confirmation, timestamped backups, a manifest
  of every change, and an uninstaller that undoes only those changes.
- **Machine-specific settings stay local**: `~/.zshrc.local` holds work
  settings and secrets and is never part of the repository.

## Supported platforms

| Platform | Shell | Packages | Notes |
| --- | --- | --- | --- |
| macOS (primary) | zsh | Homebrew | Reference setup. WezTerm runs here. |
| Windows 11 + WSL | zsh or bash in WSL | apt, dnf, pacman, zypper, apk | WezTerm runs on Windows; `--windows-wezterm` copies its config. |
| Linux | zsh or bash | apt, dnf, pacman, zypper, apk | `--release-binaries` fills gaps in older distributions. |
| Unraid | bash | none | Explicit `--unraid` mode. Minimal, and no change to `/boot`. |

## Prerequisites

- `git` and `bash` (any version from 3.2).
- macOS: [Homebrew](https://brew.sh). The installer never runs a remote
  install script; it asks you to install Homebrew yourself.
- Linux and WSL: a supported package manager and `sudo`, or use
  `--no-packages` with `--release-binaries`.
- A Nerd Font in the terminal emulator for the prompt icons. On macOS the
  installer adds `font-caskaydia-mono-nerd-font`. On Windows, install
  "CaskaydiaMono Nerd Font" from
  [nerdfonts.com](https://www.nerdfonts.com/font-downloads) for all users.

## Quick installation

```sh
git clone https://github.com/gweilo852/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh --dry-run   # preview every change
./install.sh             # shows the plan again and asks before it starts
exec zsh                 # or open a new terminal
```

Options:

| Option | Effect |
| --- | --- |
| `-n`, `--dry-run` | Show what would change. Change nothing. |
| `-y`, `--yes` | Do not ask for confirmation. Needed when there is no terminal. |
| `--no-packages` | Link configuration only. |
| `--release-binaries` | Linux, WSL, Unraid: install missing tools from pinned, SHA-256-verified release archives into `~/.local/bin`. |
| `--windows-wezterm` | WSL: copy the WezTerm config to `%USERPROFILE%\.wezterm.lua`. |
| `--unraid` | Required on Unraid. |
| `--skip-validate` | Skip the `doctor.sh --quick` check at the end. |

What the installer does:

1. Detects macOS, Linux, WSL or Unraid.
2. Checks for `git` and `curl`.
3. Installs missing packages (Homebrew, or the Linux package manager).
4. Moves each existing file it replaces to `~/.dotfiles-backups/<timestamp>/`.
5. Links the managed files:

   | Link | Target in the repository |
   | --- | --- |
   | `~/.zshrc` | `config/zsh/zshrc` |
   | `~/.config/starship.toml` | `config/starship/starship.toml` |
   | `~/.config/wezterm/wezterm.lua` | `config/wezterm/wezterm.lua` (macOS, Linux) |
   | `~/.tmux.conf` | `config/tmux/tmux.conf` |

6. Adds a marked block to `~/.bashrc` that sources `config/bash/bashrc`,
   and an `include.path` to `~/.gitconfig` for `config/git/config`.
7. Moves your previous `~/.zshrc` content to `~/.zshrc.local` (mode 600).
   Lines that would initialize something twice (Oh My Zsh, Starship,
   compinit, plugins, kube-ps1, history settings) are disabled with a
   `: # [dotfiles]` prefix. Everything else is kept as it was.
8. Runs `scripts/doctor.sh --quick`.
9. Prints a summary with the backup and manifest locations.

Running it again changes nothing when everything is already in place.

### the-beast (Windows 11 with WSL)

In the WSL distribution:

```sh
sudo apt-get install -y git curl zsh
git clone https://github.com/gweilo852/dotfiles.git ~/dotfiles
cd ~/dotfiles
./install.sh --dry-run --windows-wezterm
./install.sh --windows-wezterm --release-binaries
chsh -s "$(command -v zsh)"   # optional: make zsh the login shell
```

On Windows:

1. Install WezTerm (`winget install wez.wezterm`).
2. Install "CaskaydiaMono Nerd Font" for all users.
3. Start WezTerm. It opens the first WSL distribution in `~`.

`--windows-wezterm` copies the file because Windows cannot follow a WSL
symlink. Run the same command again after you change `wezterm.lua`.

### Unraid (Tower)

See [docs/installation.md](docs/installation.md#unraid) for the full,
safe procedure. In short, from the Unraid terminal:

```sh
cd /mnt/user/appdata
git clone https://github.com/gweilo852/dotfiles.git
cd dotfiles
./scripts/bootstrap-unraid.sh --dry-run
./scripts/bootstrap-unraid.sh --release-binaries
```

Unraid mode installs no packages, keeps state and backups next to the
repository, and never writes to `/boot`. The links live in `/root`, which
Unraid rebuilds at boot. To restore them automatically, add
`platforms/unraid/user-script.sh` to the User Scripts plugin yourself.

## Manual installation

Every step of the installer can be done by hand:

```sh
mkdir -p ~/.dotfiles-backups/manual ~/.config/wezterm
mv ~/.zshrc ~/.dotfiles-backups/manual/ 2>/dev/null
ln -s ~/dotfiles/config/zsh/zshrc            ~/.zshrc
ln -s ~/dotfiles/config/starship/starship.toml ~/.config/starship.toml
ln -s ~/dotfiles/config/wezterm/wezterm.lua  ~/.config/wezterm/wezterm.lua
ln -s ~/dotfiles/config/tmux/tmux.conf       ~/.tmux.conf
echo '. ~/dotfiles/config/bash/bashrc' >> ~/.bashrc
git config --global --add include.path ~/dotfiles/config/git/config
cp ~/dotfiles/config/zsh/zshrc.local.example ~/.zshrc.local && chmod 600 ~/.zshrc.local
```

Then install the tools listed in [docs/tools.md](docs/tools.md).
`./uninstall.sh` cannot undo manual steps, because they are not in the
manifest.

## Everyday use

```sh
ll                     # long listing with icons, directories first
ll --git               # long listing with Git status for each file
lt                     # tree, two levels deep
bat ~/.config/starship.toml   # view a file with syntax highlighting
catp file.txt          # bat without the pager
z ghost-tower          # jump to the most-used directory that matches
zi                     # choose a directory from a fuzzy list
duf                    # disk usage for each mounted filesystem
git diff               # diffs through delta, with line numbers
k get pods             # kubectl with colour (kubecolor)
ktx / kn               # switch Kubernetes context / namespace
reload                 # restart the shell after a configuration change
```

Aliases work only at the interactive prompt. Scripts always get the standard
commands. To bypass an alias at the prompt, use `command ls` or `\ls`. Note
that `ls` is eza: some GNU and BSD flags differ (for example `ls -t` needs a
field name in eza). Use `command ls -ltr` for the classic form.

More examples are in [docs/tools.md](docs/tools.md).

### The command-duration indicator

When a command runs for 3 seconds or more, the next prompt shows how long it
took, for example `󰔟 12s` or `󰔟 1m4s`. Quick commands show nothing. To change
the threshold, edit `min_time` (milliseconds) under `[cmd_duration]` in
`config/starship/starship.toml`.

### The Kubernetes context

| Real context | Displayed as | Colour |
| --- | --- | --- |
| `gke_<project>_europe-west4_deephaven-emea-prd-deephaven` | `deephaven-emea-prd` | red |
| `gke_<project>_europe-west4_deephaven-emea-prd-deephaven-prd2` | `deephaven-emea-prd2` | red |
| `gke_<project>_europe-west4_cloudtools-global-prd-cloudtools` | `cloudtools-global-prd` | red |
| `gke_<project>_us-east4_cloudtools-us-tst-cloudtools` | `cloudtools-us-tst` | blue |
| `gke_<project>_europe-west4_kafka-emea-tst-kafka` | `kafka-emea-tst` | blue |
| `gke_<project>_europe-west4_deephaven-emea-stg-deephaven` | `deephaven-emea-stg` | yellow |
| `keymaster.<domain>-apac-kafka-prod` | `km:apac-kafka-prod` | red |

Only the display changes; `kubectl config current-context` still shows the
real name. To add a pattern, see
[docs/kubernetes-prompt.md](docs/kubernetes-prompt.md).

## Keyboard shortcuts

| Keys | Action |
| --- | --- |
| Ctrl+R | Fuzzy search of the command history (fzf). |
| Ctrl+T | Fuzzy file picker; inserts the path. Shows a bat preview. |
| Alt+C | Fuzzy directory picker; changes to it. On macOS use the **left** Option key in WezTerm. |
| Right arrow or Ctrl+E | Accept the grey autosuggestion. |
| Alt+F | Accept one word of the autosuggestion. |
| Tab | Completion menu; arrow keys move through it. |
| `**` then Tab | fzf completion, for example `vim **<Tab>` or `kill -9 **<Tab>`. |

tmux keeps the `Ctrl+B` prefix. F9 goes to the last window and F10 to the
next window.

## Low-glare colours and fonts

The theme is Catppuccin Macchiato, a dark blue-grey base (`#24273a`) that
is softer than black, with pastel accents. On top of it:

- Text is `#b8c0d9`, one step dimmer than the scheme's `#cad3f5`.
- The ANSI "white" is the same dimmer colour; only bright white is full text.
- The background is fully opaque, so bright windows behind do not show.
- The cursor is a steady bar in a muted grey, with no blinking.
- bat, delta and fzf use the same palette (bat uses the terminal's ANSI
  colours; delta uses muted red and green backgrounds).
- Autosuggestions and comments are grey (`#6e738d`) so they stay quiet.

To adjust one machine, create `~/.config/wezterm/wezterm_local.lua` (on
Windows `%USERPROFILE%\wezterm_local.lua`) from
`config/wezterm/wezterm_local.example.lua`:

```lua
return function(config, wezterm)
  config.font_size = 12.0                                    -- size
  config.font = wezterm.font('CaskaydiaMono Nerd Font Mono', -- weight
    { weight = 'Regular' })
  config.foreground_text_hsb = { hue = 1.0, saturation = 1.0, brightness = 0.9 }
end
```

`brightness` below 1.0 dims all text. WezTerm reloads the file when you
save it. To change these for every machine, edit
`config/wezterm/wezterm.lua` instead. See
[docs/customization.md](docs/customization.md).

## Updating

```sh
cd ~/dotfiles
git pull
./install.sh --dry-run   # only new links or packages show up
./install.sh
exec zsh
```

Most changes need no reinstall, because the files are symlinks. On WSL,
re-run `./install.sh --windows-wezterm` to copy a changed `wezterm.lua`.

## Uninstallation

```sh
./uninstall.sh --dry-run
./uninstall.sh
```

The uninstaller reads the manifest
(`~/.local/state/dotfiles/manifest.tsv`) and:

- removes only links and blocks that the installer made, and only if they
  are unchanged (a file you replaced is left alone, with a warning);
- restores the newest backup of each file, when nothing else is in its place;
- removes the `include.path` from `~/.gitconfig`;
- keeps packages, `~/.zshrc.local`, `wezterm_local.lua` and all backups.

The Oh My Zsh directory (`~/.oh-my-zsh`) is never touched. Delete it
yourself when you no longer need it.

## Customization

- Per machine: `~/.zshrc.local`, `~/.tmux.conf.local`, `wezterm_local.lua`,
  and your own lines in `~/.bashrc` after the dotfiles block.
- Everywhere: edit the files in `config/` and commit.

Details: [docs/customization.md](docs/customization.md).

## Troubleshooting

Run the health check first:

```sh
~/dotfiles/scripts/doctor.sh
```

It reports missing tools, unmanaged files, duplicate initialization,
configuration errors, prompt duplication and shell startup time. Common
problems and fixes are in [docs/troubleshooting.md](docs/troubleshooting.md).

## Security

- The repository holds configuration only. Credentials, tokens, kubeconfig
  files, SSH keys and shell history never belong in it.
- Secrets go in `~/.zshrc.local`. The installer creates it with mode 600, and
  `doctor.sh` warns when a file with credentials is readable by others.
- `scripts/test.sh` scans tracked files for credential patterns, and for
  private terms listed in `~/.config/dotfiles/denylist` (kept outside the
  repository, one term per line). It also runs `gitleaks` when installed.
- The installer never pipes a download into a shell. Release archives are
  pinned and checked against SHA-256 values in
  `platforms/linux/release-binaries.tsv` before extraction.
- `sudo` is used only for the Linux package manager. `--no-packages` avoids it.
- `~/.ssh` and the Git identity in `~/.gitconfig` are not managed.
- Backups can contain secrets from your old `~/.zshrc`. The backup directory
  is mode 700. Delete old backups when you no longer need them.

## Repository layout

```text
dotfiles/
├── install.sh, uninstall.sh       installer and uninstaller
├── scripts/
│   ├── lib.sh                     shared functions (detection, backups, manifest)
│   ├── bootstrap-macos.sh         Homebrew packages
│   ├── bootstrap-linux.sh         apt, dnf, pacman, zypper, apk packages
│   ├── bootstrap-unraid.sh        Unraid preflight, then install.sh --unraid
│   ├── install-release-binaries.sh  pinned, verified release archives
│   ├── doctor.sh                  health check of an installed machine
│   └── test.sh                    automated validation
├── config/
│   ├── wezterm/                   wezterm.lua and a local override example
│   ├── starship/starship.toml     prompt and Kubernetes rules
│   ├── zsh/                       zshrc, completion.zsh, plugins.zsh, local example
│   ├── bash/bashrc                bash for Linux, WSL and Unraid
│   ├── shell/                     env.sh and aliases.sh, shared by zsh and bash
│   ├── tmux/tmux.conf
│   └── git/config                 delta and diff settings
├── platforms/
│   ├── macos/Brewfile
│   ├── linux/                     package names and release archive table
│   └── unraid/user-script.sh      optional relink at boot
├── tests/                         Kubernetes prompt cases and test
└── docs/                          installation, customization, tools, Kubernetes, troubleshooting
```

Maintainers and coding agents: read [AGENTS.md](AGENTS.md) first.
