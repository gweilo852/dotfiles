# AGENTS.md

Instructions for coding agents and human maintainers of this repository.
They apply to every tool (Claude Code, Codex, or another agent). Read this
file before you change anything.

## Purpose

A portable terminal environment: WezTerm, Starship, zsh, bash, tmux, Git
diff settings and modern command-line tools, with one look and one set of
shortcuts on every machine. It is a maintained project, not a backup of one
machine. Machine-specific content does not belong here.

## Supported platforms

| Platform | Detection (`scripts/lib.sh: detect_platform`) | Shell | Packages |
| --- | --- | --- | --- |
| macOS | `uname -s` = Darwin | zsh | Homebrew (`platforms/macos/Brewfile`) |
| Linux | Linux, not WSL | zsh or bash | apt-get, dnf, pacman, zypper, apk (`platforms/linux/packages.tsv`) |
| WSL | Linux and `WSL_DISTRO_NAME` or "microsoft" in `/proc/version` | zsh or bash | as Linux |
| Unraid | `/etc/unraid-version` exists (checked first; cannot be overridden) | bash | none |

## Architecture

- `install.sh` parses options, applies the safety gates, installs packages
  through `scripts/bootstrap-*.sh`, links configuration with the helpers in
  `scripts/lib.sh`, then runs `scripts/doctor.sh --quick`.
- `scripts/lib.sh` owns platform detection, backups, the manifest, links,
  marked blocks and the `.zshrc` migration. Keep it compatible with bash 3.2.
- `uninstall.sh` reads the manifest and undoes only recorded changes.
- `config/zsh/zshrc` loads, in order: Homebrew and PATH, `config/shell/env.sh`,
  history options, `completion.zsh` (compinit once), `config/shell/aliases.sh`,
  `~/.zshrc.local`, then `plugins.zsh` (fzf, zoxide, autosuggestions,
  Starship, syntax highlighting last).
- `config/bash/bashrc` is sourced from a marked block in `~/.bashrc` and
  uses the same `env.sh` and `aliases.sh`. At its end is the opt-in
  interactive zsh handoff: a one-time `PROMPT_COMMAND` hook that runs
  `exec zsh` before the first prompt.
- `config/shell/zsh-handoff.sh` (POSIX sh) is the only place that decides
  whether the handoff applies. It reads, never executes,
  `~/.config/dotfiles/local.conf` (`DOTFILES_INTERACTIVE_ZSH`,
  `DOTFILES_ZSH`). bashrc, `config/tmux/shell.sh`, `doctor.sh`,
  `install.sh` and the tests all use it.
- `config/shell/tmux.sh` defines the tmux helpers (`tm`, `tmux-workspace`,
  `tmux-send`) only when the name is free, so user definitions win.
- `config/tmux/tmux.conf` is the single tmux config. It uses no plugins.
  Version-sensitive settings must work on tmux 2.6. `clipboard.sh` picks
  the local clipboard tool; OSC 52 (`set-clipboard on`) is the main path.
  Unraid gets a minimal profile through an `if-shell` on
  `/etc/unraid-version`. It runs `shell.sh` on every load, which sets
  `default-shell` to zsh when the handoff applies, and otherwise restores
  the server's first value. `shell.sh` addresses only the server in
  `$TMUX`, never the default socket.
- `config/starship/starship.toml` holds the prompt and the ordered Kubernetes
  context rules. `tests/k8s-contexts.tsv` lists the expected display for each
  context pattern.

## Configuration ownership

| Path on the machine | Owner | Rule |
| --- | --- | --- |
| `~/.zshrc`, `~/.tmux.conf`, `~/.config/starship.toml`, `~/.config/wezterm/wezterm.lua` | repository (symlink) | Edit the file in `config/`. |
| `~/.bashrc` | user | The repository owns only its marked block. |
| `~/.gitconfig` | user | The repository owns only one `include.path` line. |
| `~/.zshrc.local`, `~/.tmux.conf.local`, `wezterm_local.lua` | user | Never create content in them after the first install, never delete them. |
| `~/.config/dotfiles/local.conf` | user | The repository owns only the `interactive-zsh` marked block, written only on `--interactive-zsh`. |
| `~/.profile`, `~/.bash_profile`, `~/.bash_login` | user | The repository owns only the `bash_profile` block, added only when the file that bash reads does not load `~/.bashrc`. |
| `~/.ssh`, kubeconfig, shell history, `~/.oh-my-zsh` | user | Never read their contents into the repository; never modify or delete them. |

## Installation safety requirements

Every change to `install.sh`, `uninstall.sh` or `scripts/` must keep these
properties. `scripts/test.sh` checks most of them.

1. `--dry-run` changes nothing, including state and backup directories.
2. A run without `--yes` asks before the first change. Without a terminal
   and without `--yes`, it stops.
3. An existing file is never overwritten silently. It is moved or copied to
   `$BACKUP_DIR` first, and the change is printed.
4. Every change is recorded in the manifest, so that uninstall can undo it.
   Add a new manifest kind to `uninstall.sh` in the same change.
5. A second run makes no changes and no new backups (idempotency).
6. Uninstall removes only unchanged managed links and blocks, restores
   backups only into empty places, and never removes packages or user files.
7. No downloaded script is executed. Release archives are pinned with a
   SHA-256 value in `platforms/linux/release-binaries.tsv`.
8. `sudo` is used only for the system package manager.
9. Unraid needs `--unraid`, the repository under `/mnt`, and installs no
   packages. Never write to `/boot`, never edit `/boot/config/go`, and never
   install plugins. Persistence at boot is a documented manual step.
10. Every optional tool can be missing. Shell files must start without
    errors when only `/usr/bin` and `/bin` are on PATH.
11. The installer never starts, stops, or sends keys to tmux sessions, and
    no shell startup file runs tmux. tmux tests use an isolated socket
    (`tmux -L`) and a temporary `$HOME`.
12. No clipboard tool, desktop or WezTerm may be required on a headless host
    (VDI, Unraid).
13. Shell initialization runs once: one compinit, one Starship init, plugins
    guarded against a second load.
14. The zsh handoff is opt-in and never runs `chsh`, edits `/etc/passwd`,
    or needs root. It runs only for an interactive bash with a terminal on
    stdin and stdout, no `-c` command, `TERM` not empty or `dumb`, no
    `DOTFILES_NO_ZSH`, no `DOTFILES_ZSH_HANDOFF` (no loop), not on Unraid,
    and a zsh that starts. Non-interactive bash, scp, sftp and scripts
    must not change. A failed handoff leaves a configured bash.
15. A check that starts an interactive shell (`bash -i`, `zsh -i`) runs
    through `no_tty` (`scripts/lib.sh`), so it never takes over the
    caller's terminal. Without it, `scripts/test.sh` stopped with SIGTTIN
    over SSH on Debian 11.
16. A file that install.sh creates has an empty backup field in the
    manifest. Uninstall deletes it only when nothing but blank lines is
    left in it.

## Testing expectations

Run before every commit:

```sh
scripts/test.sh
scripts/test-clean-install.sh
```

It checks shell syntax (bash and zsh), shellcheck, the WezTerm config, the
Starship TOML and every Kubernetes display case, tmux and Git config,
platform detection, installer dry run, backups, idempotency, migration,
startup with and without optional tools, uninstall and restore, Unraid
refusals, and secret leakage. A check whose tool is missing is skipped.

- Add a row to `tests/k8s-contexts.tsv` for every new Kubernetes rule.
- Never hardcode project names, Jira keys, hosts or paths in shared files.
  Machine workflows belong in `~/.zshrc.local` and `~/.tmux.conf.local`.
- Add a test to `scripts/test.sh` for every new installer behaviour.
- Installer tests must use the temporary `$HOME` in `scripts/test.sh`. Do
  not run `install.sh` against the real home directory during development
  unless the owner asks for it.
- `scripts/doctor.sh` checks a real installed machine. It changes nothing.
- `scripts/test-clean-install.sh` runs the real installer and uninstaller
  in one `mktemp -d` directory under `/tmp` (`HOME`, `XDG_*`,
  `TMUX_TMPDIR`). It blocks sudo, package managers, chsh and downloads,
  and checks that the real home is unchanged. Add a scenario there for
  every new installer option. Do not reimplement installer logic in it.
- Test interactive behaviour on a real pseudo-terminal with
  `tests/pty-run.py` when practical. Simulated `bash -i -c` is not enough
  for the handoff.
- tmux tests use `-L` with a unique name or a `TMUX_TMPDIR` inside the test
  directory. Never use the default socket, and never kill a server that
  the test did not start.
- awk must work with mawk 1.3.4 (Debian 11): no regex intervals such as
  `{64}`.
- CI (`.github/workflows/test.yml`) runs both suites on Ubuntu, macOS and
  Debian 11. Keep it unprivileged and free of secrets.
- Report test results with their real output. Say which checks were skipped.

## Security rules

- Never commit credentials, tokens, private keys, kubeconfig content, SSH
  configuration, shell history, or values of environment variables.
- Never commit employer names, internal hostnames, internal domains, cloud
  project IDs or user names. Kubernetes rules must stay generic (for example
  `^gke_[^_]+_[^_]+_...`). Use fictitious names such as `acme` and
  `example.net` in tests and docs.
- When you inspect a machine, do not print secret values. Mask them.
- Private terms for the leak check live in `~/.config/dotfiles/denylist`,
  outside the repository. Never copy that file into the repository.
- Do not weaken the secret scan in `scripts/test.sh` to make a test pass.

## Platform-specific limitations

- macOS: `/bin/bash` is 3.2. Scripts and `config/bash/bashrc` must not use
  associative arrays, `mapfile`, `${var,,}` or other bash 4 features.
- macOS: WezTerm's left Option key acts as Alt (for fzf Alt+C); the right
  Option key types special characters.
- WSL: WezTerm runs on Windows. `--windows-wezterm` copies (not links) the
  config to `%USERPROFILE%\.wezterm.lua`. The font must be installed in
  Windows.
- Debian and Ubuntu: `bat` is `batcat`, and old releases lack `eza`,
  `starship` or a recent `fzf`. The aliases and plugin loaders handle this;
  `--release-binaries` fills the gaps.
- Debian 11: bash 5.1, zsh 5.8, tmux 3.1c, mawk, fzf 0.24 (no `fzf
  --bash`/`--zsh`), zoxide 0.4.3. `~/.profile` loads `~/.bashrc` and then
  adds `~/.local/bin` again.
- Active Directory accounts: the login shell cannot change. Use
  `--interactive-zsh`. `$SHELL` still reports bash; check the process.
- Linux VDI: often headless, without root, behind a proxy, reached over SSH.
  The WezTerm config is linked on Linux only when `wezterm` exists, zsh is
  configured only when zsh exists, and package installation stops cleanly
  without sudo rights. `scripts/preflight.sh` is the read-only check.
- Unraid: `/root` is in RAM and rebuilt at boot; `/boot` is FAT32 (no
  symlinks, no exec). There is no package manager and usually no zsh, so
  Unraid uses bash. State and backups live in `<repo>/.state` and
  `<repo>/.backups`.

## Commit and pull request style

Keep commits focused. Describe what changes and why, and list the tests you
ran. Do not include machine-specific or private information.
