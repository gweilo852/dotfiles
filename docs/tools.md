# Tools

Every tool is optional. When one is missing, the alias falls back to the
standard command, and the shell starts without errors.

| Tool | Purpose | Fallback when missing |
| --- | --- | --- |
| [Starship](https://starship.rs) | Prompt | plain two-line prompt |
| [zsh-autosuggestions](https://github.com/zsh-users/zsh-autosuggestions) | Suggestions from history | none |
| [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting) | Highlights the command as you type | none |
| [zoxide](https://github.com/ajeetdsouza/zoxide) | Jump to frequent directories | `cd` |
| [fzf](https://github.com/junegunn/fzf) | Fuzzy search (history, files, directories) | standard Ctrl+R |
| [eza](https://github.com/eza-community/eza) | File listings | `ls` with colour |
| [bat](https://github.com/sharkdp/bat) | File viewer with highlighting | `cat` |
| [delta](https://github.com/dandavison/delta) | Git diffs | `less` |
| [duf](https://github.com/muesli/duf) | Disk usage | `df -h` |
| [tmux](https://github.com/tmux/tmux) | Terminal multiplexer | none |

Package names: `platforms/macos/Brewfile` and `platforms/linux/packages.tsv`.

## Starship

The prompt. See the README for each part and
[kubernetes-prompt.md](kubernetes-prompt.md) for the Kubernetes rules.

```sh
starship explain        # what each part of the current prompt means
starship timings        # how long each module takes
starship print-config   # the effective configuration
```

## zsh-autosuggestions

As you type, grey text shows the most recent matching command from history.

- Right arrow or Ctrl+E: accept the whole suggestion.
- Alt+F: accept the next word.
- Keep typing to ignore it.

## zsh-syntax-highlighting

Colours the command line before you press Enter: a known command is green, an
unknown command is red, strings are yellow. A red command name usually means
a typing error.

## zoxide

zoxide learns the directories you visit.

```sh
z ghost-tower      # the most frequent directory whose path matches "ghost-tower"
z dot conf         # several words must all match, in order
z -                # the previous directory
zi                 # pick from a fuzzy list (needs fzf)
zoxide query -l    # list what zoxide knows, best first
```

## fzf

```sh
<Ctrl+R>           # search history; Enter puts the command on the line
<Ctrl+T>           # pick files; inserts the paths (preview with bat)
<Alt+C>            # pick a directory and cd into it (preview with eza)
vim **<Tab>        # fuzzy completion for paths
kill -9 **<Tab>    # fuzzy completion for processes
ssh **<Tab>        # fuzzy completion for hosts
git log --oneline | fzf     # filter any list
```

In the list: type to filter, Ctrl+J and Ctrl+K (or the arrows) to move, Tab
to select several, Enter to accept, Esc to cancel.

On macOS, Alt+C needs the **left** Option key in WezTerm (configured).

## eza

```sh
ls                 # eza with icons, directories first
ll                 # long listing, hidden files included
ll --git           # long listing with the Git status of each file
ll -s modified     # sort by modification time (eza uses -s, not -t)
la                 # short listing with hidden files
lt                 # tree, two levels
lt --level=4       # deeper tree
command ls -ltr    # the system ls, for classic flags
```

## bat

```sh
bat ~/.config/starship.toml    # view with highlighting, line numbers and a pager
bat -A file.txt                # show tabs, spaces and line endings
bat -r 20:40 file.py           # lines 20 to 40
catp file.txt                  # no pager, for short files
git show HEAD:README.md | bat -l md
```

`BAT_THEME=ansi` makes bat use the terminal palette, so it matches the low-glare
colours. On Debian and Ubuntu the command is `batcat`; the `bat` alias covers it.

## delta

delta is the Git pager:

```sh
git diff           # line numbers, muted red and green backgrounds
git diff --staged
git log -p
git show HEAD~1
git add -p         # interactive staging with delta colours
```

Inside the pager, `n` and `N` jump to the next and previous file.
To compare two files outside Git: `delta old.txt new.txt`.

## duf

```sh
duf                # every mounted filesystem, grouped
duf --only local   # local disks only
duf /mnt/user      # one path (useful on Unraid)
```

## tmux

```sh
tm ghost-tower            # attach to or create a session (helper)
tmux new -s work          # new session named "work"
tmux attach -t work       # attach to it
tmux ls                   # list sessions
```

Inside tmux: `Ctrl+B d` detaches, `Ctrl+B c` opens a window, `Ctrl+B ,`
renames it, F9 goes to the last window, F10 to the next. Mouse support is
on. The full guide, with keys, clipboard and agent workflows, is
[tmux.md](tmux.md).

## Kubernetes helpers

When the tools are installed:

```sh
k get pods -A      # kubecolor (or kubectl)
ku get nodes       # plain kubectl
ktx                # kubectx: switch context
kn monitoring      # kubens: switch namespace
```

## Updating the pinned release archives

`--release-binaries` uses `platforms/linux/release-binaries.tsv`. To update a
tool, change the version, URL and SHA-256 value together. Take the value from
the release's checksum file or the GitHub API (`digest` field of the asset),
then download the archive and confirm it:

```sh
curl -fsSLO <url> && shasum -a 256 <file>
```

Then run `scripts/test.sh`.
