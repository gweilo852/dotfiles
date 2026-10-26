# Customization

Two rules:

- A change for **every machine** goes into `config/` and is committed.
- A change for **one machine** goes into a local file that the repository
  never manages.

## Local files

| File | Loaded by | Use it for |
| --- | --- | --- |
| `~/.zshrc.local` | `~/.zshrc`, after completion and aliases, before plugins and the prompt | work settings, secrets, PATH entries, extra aliases and functions, `TMUX_HOST_LABEL` |
| `~/.bashrc` (after the dotfiles block) | bash | the same, for bash |
| `~/.tmux.conf.local` | `~/.tmux.conf`, at the end | tmux overrides |
| `~/.config/wezterm/wezterm_local.lua` (Windows: `%USERPROFILE%\wezterm_local.lua`) | `wezterm.lua`, at the end | font size, weight, brightness |

Keep `~/.zshrc.local` private: `chmod 600 ~/.zshrc.local`.

Because `~/.zshrc.local` loads before the plugins, you can set plugin
variables there:

```sh
ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=#5b6078'   # darker suggestions
export FZF_DEFAULT_OPTS='--height=60% --layout=reverse'
export BAT_THEME='Nord'
```

Most values in `config/shell/env.sh` are defaults, so a value that you set
in a local file wins.

## WezTerm

### Font size

```lua
-- wezterm_local.lua
return function(config, wezterm)
  config.font_size = 12.0
end
```

`Ctrl` + `+` / `-` / `0` (`Cmd` on macOS) change the size for the current
window only.

### Font weight

The default is `DemiBold`, which suits a dark background. Lighter options
are `'Regular'` and `'Medium'`; heavier is `'Bold'`:

```lua
config.font = wezterm.font('CaskaydiaMono Nerd Font Mono', { weight = 'Medium' })
```

To list what is installed: `wezterm ls-fonts --list-system | grep -i caskaydia`.

### Brightness and contrast

- Dim all text: `config.foreground_text_hsb = { hue = 1.0, saturation = 1.0, brightness = 0.9 }`.
  Values below 1.0 are dimmer.
- Change the text colour: `config.colors.foreground = '#a5adcb'` (dimmer) or
  `'#cad3f5'` (the scheme's full text colour).
- Darker background: `config.colors.background = '#1e2030'` (Macchiato
  "mantle").
- Lighter or darker selection: `config.colors.selection_bg`.

Keep the background opaque. Transparency lets bright windows show through,
which is what this setup avoids.

### Line spacing and padding

`config.line_height` (default 1.1) and `config.window_padding`.

## Starship

Edit `config/starship/starship.toml`. Colours come from the
`[palettes.catppuccin_macchiato]` table, so a style such as `"bold blue"`
uses the Macchiato blue. Useful settings:

- `[cmd_duration] min_time`: the threshold for the duration indicator, in
  milliseconds (default 3000).
- `[directory] truncation_length`: how many path parts to show (default 3).
- `[os.symbols]`: icons for each operating system.
- Kubernetes rules: see [kubernetes-prompt.md](kubernetes-prompt.md).

Check a change at once:

```sh
starship print-config >/dev/null   # prints errors, if any
scripts/test.sh                    # full validation
```

To use a different config on one machine, set `STARSHIP_CONFIG` in
`~/.zshrc.local`.

On a console without a Nerd Font (for example a browser terminal), the icons
show as boxes. Set `STARSHIP_CONFIG` to a copy that uses
`starship preset plain-text-symbols` there.

## zsh

- Aliases for every machine: `config/shell/aliases.sh` (shared with bash).
  Guard each alias with a check that the tool exists.
- Options and history: `config/zsh/zshrc`.
- Completion: `config/zsh/completion.zsh`. To cache another generated
  completion script, add a line such as
  `_dotfiles_cache_completion gh gh completion -s zsh`.
- Plugins: `config/zsh/plugins.zsh`. Keep syntax highlighting last.

After a change: `reload` (which runs `exec zsh`).

## tmux

The prefix is `Ctrl+B`. The status bar shows `TMUX_HOST_LABEL`, which
defaults to the short host name in capitals. Set it per machine in
`~/.zshrc.local`, for example `export TMUX_HOST_LABEL="MAC"`.

## Git

`config/git/config` sets delta as the pager (with a fallback to `less`),
zdiff3 conflict markers and moved-line colours. Your name, email and any
other settings stay in `~/.gitconfig`. A setting in `~/.gitconfig` after the
include line overrides the repository value.
