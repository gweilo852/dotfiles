# Active Directory environments: zsh without changing the login shell

On a corporate Linux VDI, your account often comes from Active Directory
(through SSSD, Winbind or another directory service), not from
`/etc/passwd`. The login shell is then set centrally. `chsh` fails or has no
effect, and you cannot get root to change it. SSH logins always start
`/bin/bash`.

The interactive zsh handoff gives you zsh anyway. The login shell does not
change.

## How it works

1. You log in. sshd starts bash as a login shell. bash reads `/etc/profile`
   and `~/.profile` (or `~/.bash_profile`), which loads `~/.bashrc`, which
   loads the managed `config/bash/bashrc`.
2. The managed bashrc checks the conditions below. When they are all true,
   it adds a one-time hook to `PROMPT_COMMAND`.
3. bash finishes all its startup files, including the rest of `~/.profile`.
   Just before the first prompt, the hook runs `exec zsh -l` (or
   `exec zsh -i` for a non-login bash). bash is replaced, not nested.
4. zsh loads `~/.zshrc` (managed) and `~/.zshrc.local`. All exported
   variables from the bash startup files reach zsh. Aliases, functions and
   unexported variables from bash do not.

The handoff happens only when all of these are true:

| Condition | Why |
| --- | --- |
| `DOTFILES_INTERACTIVE_ZSH=1` in `~/.config/dotfiles/local.conf` (or the environment) | Opt-in, per machine. |
| bash is interactive (`$-` contains `i`) | Scripts never change shell. |
| No `bash -c` command (`$BASH_EXECUTION_STRING` is empty) | `ssh host cmd`, `bash -ic cmd`, editor and IDE environment probes run their command in bash. |
| A terminal on stdin and stdout | scp, sftp, rsync, Ansible and pipes are not affected. |
| `TERM` is set and is not `dumb` | Emacs TRAMP and similar tools keep bash. |
| `DOTFILES_ZSH_HANDOFF` is not set | A bash started from the handed-off zsh stays bash (no loop). |
| `DOTFILES_NO_ZSH` is not set | The escape hatch. |
| Not Unraid | Unraid always uses bash. |
| zsh is found (`DOTFILES_ZSH`, or `zsh` on PATH) and `zsh -f -c 'exit 0'` succeeds | A missing or broken zsh never locks you out; bash stays. |

The bash session is fully configured before the hook runs. If zsh cannot
start, you get a warning and a working bash.

## Enable

```sh
cd ~/dotfiles
./install.sh --dry-run --no-packages --interactive-zsh
./install.sh --no-packages --interactive-zsh        # add --yes to skip the prompt
```

The installer:

- adds `DOTFILES_INTERACTIVE_ZSH=1` to `~/.config/dotfiles/local.conf`, in
  a marked block that is recorded in the manifest;
- makes sure that a bash login reaches `~/.bashrc`. When the profile file
  that bash reads does not load `~/.bashrc`, it adds a block. When there is
  no profile file at all, it creates `~/.profile`.

Log out and log in again. To check:

```sh
ps -o comm= -p $$        # zsh: the shell that really runs
echo $SHELL              # still /bin/bash: the account's login shell
scripts/doctor.sh        # "interactive zsh handoff: on (...)"
```

`$SHELL` keeps reporting `/bin/bash`, because it reflects the account's
configured login shell. Use the process (`ps -o comm= -p $$`) to see the
current shell.

### Settings

`~/.config/dotfiles/local.conf` is machine-local and never in the
repository (example: `config/dotfiles/local.conf.example`). The file is
read, not executed: only `NAME=value` lines count, and the last one wins.
An environment variable of the same name wins over the file.

| Setting | Meaning |
| --- | --- |
| `DOTFILES_INTERACTIVE_ZSH=1` | Turn the handoff on (`0` or no line: off). |
| `DOTFILES_ZSH=/path/to/zsh` | Use this zsh. Default: the first `zsh` on PATH. Must be an absolute path. |

## Disable

For one session, from your Mac:

```sh
ssh -t vdi 'DOTFILES_NO_ZSH=1 exec bash -l'
```

For one shell, on the VDI: `DOTFILES_NO_ZSH=1 bash -i`.

Permanently:

```sh
./install.sh --no-interactive-zsh   # backs up local.conf, removes the block
```

Or edit `~/.config/dotfiles/local.conf` and set
`DOTFILES_INTERACTIVE_ZSH=0`. `./uninstall.sh` also removes the setting,
with the rest of the managed configuration.

## tmux

When the handoff is on, `config/tmux/shell.sh` sets the tmux
`default-shell` to the same zsh, so new windows and panes start zsh
directly. When it is off, tmux keeps its own choice (`$SHELL` of the tmux
server, or the login shell). See [tmux.md](tmux.md#shell-for-new-windows).

A running tmux server keeps its settings. After you turn the handoff on or
off, press `prefix r` in each server, or start a new server. Windows that
already exist keep their shell.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| SSH login stays in bash | `scripts/doctor.sh`: the handoff line gives the reason. Check `echo $TERM` (must not be empty or `dumb`) and `env \| grep DOTFILES_`. |
| "SSH login path ... does not load ~/.bashrc" | Run `./install.sh` again, or add `. ~/.bashrc` to the profile file that bash reads. |
| Something after the dotfiles block in `~/.bashrc` or `~/.profile` replaces `PROMPT_COMMAND` | Append to it instead: `PROMPT_COMMAND="${PROMPT_COMMAND:+$PROMPT_COMMAND; }mycmd"`. Otherwise the hook never runs, and bash stays (still fully configured). |
| A work variable is missing in zsh | Only exported variables cross the `exec`. Add `export`, or set it in `~/.zshrc.local`. Aliases and functions belong in `~/.zshrc.local` too. |
| "dotfiles: cannot start ..." | zsh is broken or missing. bash stays. Fix zsh, or set `DOTFILES_ZSH`. |
| A tool says the shell is bash | It reads `$SHELL`. That is expected; see above. |
| You cannot log in at all | Run `ssh -t vdi 'DOTFILES_NO_ZSH=1 exec bash --noprofile --norc'`, then `./install.sh --no-interactive-zsh`. |

Non-interactive SSH commands (`ssh vdi starship --version`) use a
non-interactive bash, which reads no profile and returns early from
`~/.bashrc`. Tools in `~/.local/bin` are then on PATH only if you add them
in `~/.bashrc` before the interactive check, or use their full path.
