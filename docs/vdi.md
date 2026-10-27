# Linux VDI installation

A work VDI is usually a managed Linux host that you reach over SSH (for
example with `tsh ssh`) from WezTerm on your Mac. It often has no desktop,
no root access, existing work settings in the shell files, and a proxy.
This guide installs the dotfiles there without disturbing any of that.

The terminal, font and colours come from WezTerm on the Mac. The VDI needs
only the shell, Starship, tmux and the command-line tools.

## Debian 11 (Bullseye)

Debian 11 works. These are the differences that matter:

| Item | Debian 11 | Effect |
| --- | --- | --- |
| bash | 5.1 | Supported. |
| zsh | 5.8 | Supported. |
| tmux | 3.1c | Supported. `doctor.sh` notes that 3.2 or later is recommended. |
| awk | mawk 1.3.4 | No regex intervals such as `{64}`; the scripts avoid them. |
| fzf | 0.24 (package) | No `fzf --bash`/`--zsh`; the key bindings load from `/usr/share/doc/fzf/examples/`. `--release-binaries` installs a current fzf only when no fzf is on PATH. |
| zoxide | 0.4.3 (package) | Works (`z`, `zi`). |
| bat | `batcat` (package) | The `bat` alias covers it. |
| starship, eza, delta, duf | not packaged | `--release-binaries` installs them into `~/.local/bin`. |
| zsh-autosuggestions, zsh-syntax-highlighting | packaged | Found in `/usr/share`. |
| `~/.profile` (from `/etc/skel`) | loads `~/.bashrc`, then adds `~/.local/bin` | An SSH login reaches the dotfiles block. In bash, `~/.local/bin` can appear twice in PATH; that is harmless, and zsh removes duplicates. |
| Account | often Active Directory | `chsh` does not work. Use the interactive zsh handoff below. |

Prerequisites: `git`, and `curl` (or `wget`) with `tar` for
`--release-binaries`. No root is needed.

## Preflight checklist

Run every step before you install. None of them changes the VDI.

1. **Connect and open a plain shell** (not inside an old tmux session, so a
   problem cannot hide behind it).
2. **Clone the repository:**

   ```sh
   git clone https://github.com/gweilo852/dotfiles.git ~/dotfiles
   cd ~/dotfiles
   ```

   Behind a proxy, `git` and `curl` use `https_proxy`. If GitHub is blocked,
   copy the repository from the Mac with `scp -r` or `rsync`.

3. **Run the preflight report:**

   ```sh
   scripts/preflight.sh
   ```

   Check its output against this list:

   | Check | What to look for |
   | --- | --- |
   | Distribution | Name and version, for example Ubuntu 22.04 or Rocky 9. |
   | sudo | "works without a password", "needs a password", or no sudo. Without rights, plan for `--no-packages --release-binaries`. |
   | Graphical session | Usually none over SSH. That is expected; the clipboard uses OSC 52. |
   | Locale | A UTF-8 locale. If not, add `export LANG=C.UTF-8` to the local shell file. |
   | Home directory | Writable, with at least ~100 MB free for release binaries. |
   | Existing files | Which shell files exist. Each one is backed up or extended, never lost. |
   | Tools | Which tools exist. All are optional. |
   | tmux | 2.6 or later (3.2 or later recommended). |

4. **Read your existing shell files** so you know what must survive:

   ```sh
   grep -nE '^(export|alias|source|\.|eval)|\(\) *\{' ~/.bashrc ~/.zshrc ~/.bash_profile ~/.profile 2>/dev/null
   ```

   Note work variables, aliases, functions, proxy settings and anything the
   VDI team added (module loads, conda, SDKs).

5. **Preview the installation:**

   ```sh
   ./install.sh --dry-run                               # with sudo rights
   ./install.sh --dry-run --no-packages --release-binaries   # without root
   ```

   Every planned change is listed: backups, links, the `~/.bashrc` block and
   the `~/.gitconfig` include. Nothing changes.

## Install

With sudo rights:

```sh
./install.sh
```

Without root (the common case on a managed VDI):

```sh
./install.sh --no-packages --release-binaries
```

`--release-binaries` installs starship, zoxide, fzf, eza, bat, delta and duf
into `~/.local/bin` from pinned GitHub archives, each checked against a
SHA-256 value. It needs `curl` (or `wget`), `tar` and access to GitHub. zsh
and tmux are not available this way; use the system packages, or ask the VDI
team to install them. Without zsh, the installer configures bash only.

The installer:

- prints the platform and distribution;
- shows the plan again and asks before the first change;
- moves files it replaces to `~/.dotfiles-backups/<timestamp>/`;
- keeps `~/.bashrc` and adds one marked block at the end;
- moves your old `~/.zshrc` to `~/.zshrc.local`, with duplicate
  initialization disabled and everything else kept;
- skips the WezTerm config (no WezTerm on the VDI);
- runs a quick health check.

### Interactive zsh (Active Directory accounts)

If `scripts/preflight.sh` reports a directory account, or `chsh` does not
work, keep bash as the login shell and let it start zsh:

```sh
./install.sh --dry-run --no-packages --interactive-zsh
./install.sh --no-packages --interactive-zsh
```

Log out and log in again. An interactive SSH login now starts zsh; `ssh vdi
COMMAND`, scp, sftp and scripts still use bash. New tmux windows start zsh
too (press `prefix r` in a running tmux server first). `$SHELL` still shows
`/bin/bash`; `ps -o comm= -p $$` shows the real shell. The full
explanation, the escape hatch and troubleshooting are in
[active-directory.md](active-directory.md).

Set a status-bar label for tmux in the local shell file:

```sh
echo 'export TMUX_HOST_LABEL="VDI"' >> ~/.zshrc.local   # or ~/.bashrc
```

## Validate

Start a new shell (`exec zsh` or `exec bash -l`), then:

```sh
scripts/doctor.sh                 # links, tools, syntax, startup, tmux
starship --version && echo "$STARSHIP_SHELL"   # prompt active
type z zi                         # zoxide
bind -X 2>/dev/null | grep -i fzf || bindkey | grep fzf   # fzf keys (bash / zsh)
tmux new-session -s check         # status bar, then prefix d
tmux kill-session -t check
```

Work through this list:

- [ ] The prompt has two lines, with the Kubernetes context if one is set.
- [ ] Ctrl+R opens the fzf history search; Ctrl+T the file picker.
- [ ] `z <part of a directory>` jumps after you visit it once.
- [ ] `ll`, `lt`, `bat`, `git diff` work (or fall back to plain tools).
- [ ] tmux shows the subdued status bar with your label.
- [ ] In tmux, `prefix [`, select with `v`, copy with `y`, then Cmd+V on the
      Mac pastes the text (OSC 52 over SSH).
- [ ] Your work aliases, variables and functions still work:
      `alias`, `env | cut -d= -f1 | sort`, `type <your function>`.
- [ ] `scripts/doctor.sh` reports no errors.
- [ ] With the handoff: a new SSH login shows `zsh` for `ps -o comm= -p $$`;
      `ssh vdi 'ps -o comm= -p $$'` shows `bash`; `scp` works;
      `tmux new-session -d -s check && tmux new-window -d -t check: &&
      tmux list-panes -s -t check -F '#{pane_current_command}'` shows `zsh`.
- [ ] `./install.sh --dry-run` reports 0 changes (idempotent).

## Dependencies

| Need | For | Package (apt / dnf) | Without root |
| --- | --- | --- | --- |
| git | clone and updates | git / git | usually present |
| curl or wget, tar | `--release-binaries` | curl / curl | usually present |
| bash 3.2+ | installer, bash config | present | present |
| zsh | zsh config (optional) | zsh / zsh | ask the VDI team |
| tmux 2.6+ | tmux config (optional) | tmux / tmux | ask the VDI team |
| starship, fzf, zoxide, eza, bat, delta, duf | tools (optional) | see `platforms/linux/packages.tsv` | `--release-binaries` |
| wl-clipboard, xclip or xsel | local clipboard (only with a desktop) | as named | not needed over SSH |
| zsh-autosuggestions, zsh-syntax-highlighting | zsh plugins (optional) | as named | clone into `~/.local/share/zsh/plugins/<name>/` |

## Restore the original configuration

To turn off only the zsh handoff:

```sh
./install.sh --no-interactive-zsh
```

If zsh breaks so that a login is unusable, log in without it:
`ssh -t vdi 'DOTFILES_NO_ZSH=1 exec bash -l'`.

If something goes wrong, the uninstaller undoes exactly what the installer
did, restores the backups and keeps `~/.zshrc.local`:

```sh
cd ~/dotfiles
./uninstall.sh --dry-run
./uninstall.sh
exec bash -l
```

If the shell is broken so badly that the uninstaller cannot run:

1. Start a shell that skips the startup files:
   `bash --noprofile --norc` (or `zsh -f`).
2. Remove the links and restore the backups by hand:

   ```sh
   ls ~/.dotfiles-backups/                       # newest timestamp last
   B=~/.dotfiles-backups/<timestamp>
   for f in .zshrc .tmux.conf .config/starship.toml; do
     [ -L ~/$f ] && rm ~/$f && [ -e "$B/$f" ] && cp -p "$B/$f" ~/$f
   done
   cp -p "$B/.bashrc" ~/.bashrc                  # removes the dotfiles block
   cp -p "$B/.gitconfig" ~/.gitconfig 2>/dev/null
   ```

3. If there was no backup of `~/.bashrc` (the file did not exist before),
   delete the lines between `# >>> dotfiles (bash) >>>` and
   `# <<< dotfiles (bash) <<<`.
4. Release binaries in `~/.local/bin` are harmless; delete them if you want.

Over SSH, you can also run a command without the startup files:
`ssh vdi -t bash --noprofile --norc`.

## Updating

```sh
cd ~/dotfiles && git pull && ./install.sh --dry-run && ./install.sh
```

`./install.sh` without `--interactive-zsh` keeps the handoff setting as it
is. To check an update without touching your home directory:

```sh
scripts/test.sh
scripts/test-clean-install.sh
```

If the clean-install test fails on the VDI only, run
`scripts/diagnose-test-env.sh` and see
[troubleshooting.md](troubleshooting.md#scriptstest-clean-installsh-fails-on-a-vdi-but-passes-elsewhere).
