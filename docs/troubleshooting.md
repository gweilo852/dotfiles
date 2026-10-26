# Troubleshooting

Start with:

```sh
~/dotfiles/scripts/doctor.sh
```

## Icons show as boxes or question marks

The terminal font is not a Nerd Font.

- macOS: `brew install --cask font-caskaydia-mono-nerd-font`, then restart
  WezTerm.
- Windows: install "CaskaydiaMono Nerd Font" for all users, then restart
  WezTerm.
- Check what WezTerm uses: `wezterm ls-fonts | head`.
- Over SSH, the font of the machine you type on matters, not the server.

## The prompt appears twice, or the old prompt comes back

Something initializes the prompt a second time. `doctor.sh` lists the lines.
Look for these in `~/.zshrc.local`, `~/.zprofile` and `~/.zshenv`:

- `eval "$(starship init zsh)"`
- `source $ZSH/oh-my-zsh.sh`, `ZSH_THEME=...`
- `PROMPT=...` or `kube_ps1`

Delete them or disable them with a leading `#`. Then `exec zsh`.

## "compinit: insecure directories"

Homebrew directories are writable by your group. The managed configuration
skips them quietly, but you can fix the permissions:

```sh
compaudit | xargs chmod g-w
```

## Completion for kubectl or helm is old or missing

The generated scripts are cached in `~/.cache/zsh/completions`. Rebuild
them:

```sh
refresh-completions
```

## Shell startup is slow

```sh
time zsh -i -c exit                  # target: well under 300 ms
zsh -i -c 'zmodload zsh/zprof; source ~/.zshrc; zprof' | head -20
```

Common causes: a slow command in `~/.zshrc.local` (such as
`source <(kubectl completion zsh)`; the managed config caches this already),
or a large Git repository for the Starship Git modules (`starship timings`).

## Alt+C types "ç" on macOS

Use the **left** Option key. The right Option key types special characters
by design. If the left key still fails, check that
`send_composed_key_when_left_alt_is_pressed = false` is not overridden in
`wezterm_local.lua`.

## `ls -t` (or another flag) fails

`ls` is eza at the prompt. Use `command ls -ltr`, or the eza form
(`ll -s modified`). Scripts are not affected.

## `bat: command not found` on Debian or Ubuntu

The package installs `batcat`. The managed aliases map `bat` to it. In a
script, call `batcat`.

## Colours look wrong inside tmux

Check that the terminal supports true colour:

```sh
printf '\e[38;2;237;135;150mred\e[0m\n'
tmux info | grep -i Tc
```

The tmux config enables true colour for `xterm-256color`. If your terminal
sets another `TERM`, add it in `~/.tmux.conf.local`:

```tmux
set -ga terminal-overrides ",wezterm:Tc"
```

## WezTerm shows a configuration error

WezTerm shows the error in a window. To check from a shell:

```sh
wezterm --config-file ~/.config/wezterm/wezterm.lua ls-fonts 2>&1 | grep -E 'ERROR|WARN'
```

An error in `wezterm_local.lua` is logged, and the main config still loads.

## The installer stopped with "not interactive"

Without a terminal (for example in a script), the installer needs `--yes`.
Preview first with `--dry-run`.

## The installer says a file "is not the managed link"

You (or another tool) replaced a managed symlink with a file. The uninstaller
leaves such files alone. To manage it again, run `./install.sh`; it backs up
the file and relinks it.

## Restoring a single file from a backup

Backups are in `~/.dotfiles-backups/<timestamp>/` (Unraid:
`<repo>/.backups/<timestamp>/`), with the same paths as in your home
directory:

```sh
ls ~/.dotfiles-backups/
cp -p ~/.dotfiles-backups/20261026-120000/.zshrc ~/.zshrc.old
```

The manifest of changes is `~/.local/state/dotfiles/manifest.tsv`.

## Unraid: everything is gone after a reboot

This is expected: Unraid rebuilds `/root` at boot. Run
`/mnt/user/appdata/dotfiles/install.sh --unraid --yes`, or set up the
User Scripts entry described in [installation.md](installation.md#after-a-reboot).
