# tmux

One tmux configuration for macOS, Linux (VDI), WSL and Unraid. It uses no
plugins and no plugin manager. Files:

| File | Role |
| --- | --- |
| `config/tmux/tmux.conf` | the configuration (`~/.tmux.conf` links to it) |
| `config/tmux/clipboard.sh` | copies to the local clipboard when a tool exists |
| `config/tmux/tmux.conf.local.example` | template for `~/.tmux.conf.local` |
| `config/shell/tmux.sh` | shell helpers: `tm`, `tmux-workspace`, `tmux-send` |

Requirements: tmux 2.6 or later; 3.2 or later is recommended. Clipboard tools
are optional. The installer never starts, stops or changes a running tmux
session. To load the new configuration into a running server, press
`prefix r`, or start a new server.

## Keys

The prefix is `Ctrl+B`. "prefix x" means: press Ctrl+B, release, press x.

| Keys | Action |
| --- | --- |
| prefix `c` | new window (in the current directory) |
| prefix `,` | rename the window |
| prefix `\|` or `%` | split side by side (current directory) |
| prefix `-` or `"` | split top and bottom (current directory) |
| prefix `h` `j` `k` `l` | move to the pane left, down, up, right |
| prefix `H` `J` `K` `L` | resize the pane (repeat without the prefix) |
| prefix `z` | zoom the pane (status shows `Z`) |
| prefix `x` | close the pane |
| prefix `0`…`9` | go to window 0…9 (numbering starts at 0) |
| F9 / F10 | last window / next window (no prefix) |
| prefix `d` | detach |
| prefix `s` or `S` | choose a session from a tree |
| prefix `(` / `)` | previous / next session |
| prefix `$` | rename the session |
| prefix `C` | new session: asks for a name, switches if it exists |
| prefix `[` | copy mode (see below) |
| prefix `]` | paste the last copied text |
| prefix `r` | reload the configuration |
| prefix `?` | list all keys |

Mouse support is on: click a pane or window, drag a border to resize, scroll
to enter copy mode, drag to select and copy. To select text with the
terminal instead, hold Shift (WezTerm) while you drag, or turn the mouse off
in `~/.tmux.conf.local`.

### Copy mode (vi keys)

| Keys | Action |
| --- | --- |
| prefix `[` | enter copy mode |
| `h` `j` `k` `l`, `w` `b`, `Ctrl+U` `Ctrl+D`, `g` `G` | move |
| `/` and `?` then `n` `N` | search forward, backward, next, previous |
| `v` | start a selection |
| `Ctrl+V` | toggle a rectangular selection |
| `y` or Enter | copy and leave copy mode |
| `q` or Escape | leave copy mode |

## Clipboard

Each copy goes to the tmux buffer and, where possible, to the system
clipboard in two ways:

1. **OSC 52.** tmux sends the copied text to the terminal (`set-clipboard
   on`). WezTerm puts it on the clipboard of the machine you type on. This
   works over SSH, so a copy on the VDI or on Unraid lands on your Mac or
   Windows clipboard.
2. **`clipboard.sh`** pipes the text to a tool on the machine where tmux
   runs, when one is usable:

| Platform | Tool | Condition |
| --- | --- | --- |
| macOS | `pbcopy` | always present |
| Linux, Wayland | `wl-copy` (package `wl-clipboard`) | `WAYLAND_DISPLAY` set |
| Linux, X11 | `xclip`, else `xsel` | `DISPLAY` set |
| WSL | `clip.exe` | WSL detected, no usable Wayland or X11 tool |
| Headless Linux, Unraid | none | input is discarded quietly |

No clipboard tool is required. On Unraid the minimal profile skips
`clipboard.sh` entirely and relies on OSC 52.

To see which tool this machine uses:

```sh
~/dotfiles/config/tmux/clipboard.sh --detect
```

On WSL, `clip.exe` can mangle non-ASCII text; OSC 52 to WezTerm does not.
Paste from the system clipboard with the terminal's paste key (Cmd+V on
macOS, Ctrl+Shift+V in WezTerm on Windows and Linux).

## Status bar

Subdued Catppuccin Macchiato on the darker "mantle" background. Only the
current window has a background colour.

```text
 MAC │ ghost-tower ●   0:infra  1:claude  2:codex           COPY host 14:05 26 Oct
```

- Left: host label, session name, and a yellow dot while the prefix is active.
  The label is `TMUX_HOST_LABEL` (set it per machine, for example `MAC`,
  `BEAST`, `VDI`, `TOWER`), else the short host name.
- Windows: index and name. `Z` marks a zoomed pane. A window turns yellow on
  activity and red on a bell, for example when an agent finishes.
- Right: `COPY` in copy mode, host name, time and date.

## Session management

```sh
tmux new-session -s ghost-tower             # new session, attached
tmux new-session -d -s ghost-tower          # new session, in the background
tmux new-window -t ghost-tower -n infra     # add a named window
tmux attach -t ghost-tower                  # attach (prefix d to detach)
tmux new-session -A -s ghost-tower          # attach, or create if missing
tmux list-sessions                          # sessions
tmux list-windows -a                        # windows of every session
tmux rename-session -t ghost-tower tower    # rename a session
tmux rename-window -t ghost-tower:1 claude  # rename a window
tmux switch-client -t CLOUD-1234            # switch, from inside tmux
tmux kill-session -t old-story              # end a session
```

Target syntax: `session`, `session:window` (name or index),
`session:window.pane`. Prefix a session name with `=` (for example
`-t =CLOUD-1234`) for an exact match; without it tmux also accepts a prefix
of the name.

### Shell helpers

`config/shell/tmux.sh` adds three helpers to zsh and bash. Each is defined
only if no command, alias or function of the same name exists, so your own
definitions win.

```sh
tm                       # session named after the current directory
tm CLOUD-1234            # attach to (or create) the story session
tmux-workspace ghost-tower infra claude codex
                         # create the session and any missing windows
tmux-workspace -d CLOUD-1234 claude terraform k8s
                         # same, without attaching
tmux-send ghost-tower:claude "run the tests and summarise failures"
```

`tmux-workspace` only adds what is missing. It never closes, renames or
restarts a window that exists, so it is safe to run again.

## Workflows

### Home: project sessions

One session per project, one window per component or agent:

```sh
cd ~/src/ghost-tower
tmux-workspace ghost-tower infra claude codex
# window "claude": run `claude`;  window "codex": run `codex`
```

Set `export TMUX_HOST_LABEL="BEAST"` (or similar) in the local shell file of
each machine, so the status bar shows where you are.

### Work: story sessions

One session per Jira story, named after the story key:

```sh
tm CLOUD-1234                                # or:
tmux-workspace CLOUD-1234 claude terraform k8s
```

Story keys and paths stay out of the repository. Put shortcuts for your own
stories, hosts and paths in `~/.zshrc.local` (or after the dotfiles block in
`~/.bashrc`), and tmux key bindings in `~/.tmux.conf.local`. A remote
session that you attach to over SSH works the same way, for example:

```sh
ssh vdi -t 'tmux new-session -A -s CLOUD-1234'
```

### Claude Code and Codex in separate windows

- Give each agent its own named window (`claude`, `codex`) so that targets
  stay stable.
- The window turns red on a bell. Claude Code can ring the terminal bell when
  it needs input: choose the terminal bell for notifications in its
  `/config` settings.
- Window names stay fixed (`automatic-rename off`), so a running program
  cannot rename `claude` to `node`.

## Sending commands to agent windows

`tmux send-keys` types into a pane as if you did. A wrong target runs the
command in the wrong place, so check the target first:

```sh
tmux list-windows -t ghost-tower -F '#{window_index} #{window_name} #{pane_current_command}'
tmux display-message -p -t '=ghost-tower:claude' '#{pane_current_command}'
```

Then send:

```sh
tmux send-keys -t '=ghost-tower:claude' -l -- 'review the last commit'
tmux send-keys -t '=ghost-tower:claude' Enter
```

- `=` makes the session match exact.
- `-l` sends the text literally; without it, words such as `Enter` or `C-c`
  become keys.
- `--` stops option parsing, so text that starts with `-` is safe.
- Send Enter separately. A short pause before it helps a TUI agent treat the
  text as typed input.
- A window with several panes receives the text in its active pane. Add
  `.N` to the target for a specific pane.

`tmux-send` does all of this. It refuses a session that does not exist, a
window name that matches zero or several windows, and a non-interactive call
without `-y`. It shows the target, the program running there and the text,
then asks for confirmation:

```text
$ tmux-send ghost-tower:claude "review the last commit"
target: ghost-tower:claude (window 1, running claude)
text:   review the last commit
send? [y/N] y
```

Use `-y` only in scripts that have already checked the target.

## Platform differences

| | macOS | Linux VDI | WSL (the-beast) | Unraid (Tower) |
| --- | --- | --- | --- | --- |
| Terminal | WezTerm | WezTerm on the Mac, over SSH | WezTerm on Windows | WezTerm over SSH |
| Clipboard | OSC 52 + pbcopy | OSC 52 (+ wl-copy/xclip/xsel with a desktop) | OSC 52 + clip.exe | OSC 52 only |
| Profile | standard | standard | standard | minimal (no helper, no date) |
| tmux source | Homebrew | distribution package | distribution package | Unraid or Nerd Tools |
| terminfo | tmux-256color | tmux-256color, else screen-256color | tmux-256color | as available |

`tmux show -gv @dotfiles_profile` prints the active profile.

## Customization

Copy `config/tmux/tmux.conf.local.example` to `~/.tmux.conf.local`. It loads
last, so its settings win. Examples in the template: mouse off, shorter
history, keys for `claude` and `codex` windows, and a key that creates your
usual windows.

## Troubleshooting

| Problem | Fix |
| --- | --- |
| Colours look wrong | `tmux info \| grep -E 'Tc\|RGB'`; outside tmux check `echo $TERM` is `xterm-256color` or `wezterm`. Add `set -ga terminal-overrides ",YOURTERM:Tc"` locally. |
| `missing or unsuitable terminal: tmux-256color` on another host | That host lacks the terminfo entry. The config falls back to `screen-256color` when tmux starts; for an old server, `tmux kill-server` and start again. |
| Copy does not reach the clipboard over SSH | WezTerm must allow OSC 52 (on by default). Check `tmux show -sv set-clipboard` is `on`. Inside nested tmux, both must have it on. |
| Copy does not reach the local clipboard | `clipboard.sh --detect`; install `wl-clipboard`, `xclip` or `xsel` if you have a desktop. |
| Text selection with the mouse does not work | Hold Shift while you drag, or `set -g mouse off` in `~/.tmux.conf.local`. |
| A key does nothing | `tmux list-keys \| grep <key>`; check `~/.tmux.conf.local`. |
| Changes do not apply | prefix `r`. Some options apply only to new windows or new servers. |
| Escape is slow in vim | `escape-time` is 10 ms; lower it in the local file if needed. |
| The status label is empty or wrong | `TMUX_HOST_LABEL` comes from the shell that created the session. Set it in the local shell file, then start a new session, or `tmux set-environment -g TMUX_HOST_LABEL VDI`. |
