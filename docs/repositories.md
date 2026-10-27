# Repositories, tmux workspaces and Git identities

Three parts stay independent:

| Part | Owns |
| --- | --- |
| dotfiles | shell configuration, the `repo` command, tmux helpers, Git identity configuration, global AI instructions |
| Story Status | work contexts, optional Jira links, worktrees, agent monitoring and telemetry |
| each Git repository | its code, its own `AGENTS.md` and its configuration |

dotfiles finds and opens repositories and worktrees. It never creates,
moves, clones or deletes a repository or a worktree.

## Layout

```text
~/projects/
├── personal/<org>/<repository>/
├── work/<org>/<repository>/
├── scratch/<repository>/
└── <scope>/<org>/.worktrees/<repository>/<context>/
```

The root is `~/projects`. To use another directory, set it in
`~/.config/dotfiles/local.conf` (or in the environment):

```sh
DOTFILES_PROJECTS=~/code
```

`./install.sh --repos` creates the root and the `personal`, `work` and
`scratch` directories, and sets up the Git identities (below). It does not
touch repositories, and there is no migration of an older layout.

## The `repo` command

`repo` works in bash and zsh and needs no extra packages (fzf is optional).

| Command | Effect |
| --- | --- |
| `repo` | choose a repository with fzf (on a terminal), else list them |
| `repo list` | list repositories: `scope/org/repo` and the path |
| `repo list --worktrees` | also list worktrees as `scope/org/repo@context` |
| `repo NAME` | `cd` to a repository. NAME is `repo`, `org/repo` or `scope/org/repo` |
| `repo root` | print the top of the current repository (or worktree) |
| `repo worktrees [NAME]` | `git worktree list` for NAME or the current repository |
| `repo tmux [-d] [NAME] [CONTEXT]` | attach to or create the repository's tmux session |

Names are matched by whole path components: `api` matches
`work/acme/api` and `personal/me/api`, but not `myapi`. When a name
matches more than one repository, `repo` lists the candidates and stops
with status 2. It never guesses. No match gives status 1 and similar
names. Worktree directories are never listed or matched unless you ask
with `--worktrees`.

A command, alias or function named `repo` that you defined first is kept;
dotfiles then does not define its own.

## tmux: one session per repository

`repo tmux` uses one tmux session for each repository, and windows inside
it for contexts (a branch, a ticket, an agent):

```sh
repo tmux acme/api              # session work/acme/api, attach or switch
repo tmux acme/api STORY-1234   # window STORY-1234; in the worktree
                                # .worktrees/api/STORY-1234 if it exists
repo tmux                       # from inside a repository or worktree
repo tmux -d acme/api review    # create without attaching
```

- The session name is `scope/org/repo`, with `.` and `:` (not allowed in
  tmux names) replaced by `_`. It is stable and does not depend on which
  other repositories exist.
- The session records its repository in the option `@dotfiles_repo`. If a
  session with that name exists for another path, or one you created by
  hand, `repo tmux` leaves it alone and uses `scope/org/repo-<hash>`
  instead, where the hash is a short checksum of the path.
- It never renames, closes or restarts a session or window. An existing
  window with the context name is selected, not recreated.
- Inside tmux it switches the client; outside it attaches.
- A session name is not treated as a Jira key, and nothing here starts an
  agent. What runs in a window is up to you (or Story Status).
- `tm` and `tmux-workspace` work as before. Existing sessions, such as a
  story session from earlier, are not migrated.

Tested with tmux 3.1c (Debian 11) and 3.8 (macOS).

## Git identities

`./install.sh --repos` keeps the personal and work identities apart with
conditional includes. It adds these to `~/.gitconfig`, which you own
otherwise (each entry is in the manifest):

```ini
[user]
	useConfigOnly = true
[includeIf "gitdir:~/projects/personal/"]
	path = <dotfiles>/config/git/identity-guard.config
	path = ~/.config/git/identity-personal
[includeIf "gitdir:~/projects/work/"]
	path = <dotfiles>/config/git/identity-guard.config
	path = ~/.config/git/identity-work
```

The identity files are yours, local and never in a repository. The
installer does not write them. Create them once:

```sh
mkdir -p ~/.config/git
git config --file ~/.config/git/identity-personal user.name "Your Name"
git config --file ~/.config/git/identity-personal user.email "you@personal.example"
git config --file ~/.config/git/identity-work user.name "Your Name"
git config --file ~/.config/git/identity-work user.email "you@work.example"
```

How the separation holds:

- The guard file clears `user.name` and `user.email` for repositories in
  a scope. The scope's identity file then sets them. If the identity file
  is missing, the guard leaves them empty, and with `useConfigOnly` Git
  refuses to commit ("Author identity unknown"). A work repository can
  therefore never commit with a personal identity from `~/.gitconfig`, and
  the reverse.
- `useConfigOnly` stops Git from guessing an identity from the host name.
- Worktrees match too: a worktree's Git directory is inside the main
  repository. Git compares `gitdir:` with the physical path of that
  directory, so for a projects root behind a symlink the installer also adds
  the physical path.
- `scratch/` and repositories outside the projects root use your global
  identity from `~/.gitconfig`, if you have one.

`scripts/doctor.sh` reports each scope's identity file. All of this works
with Git 2.30.2 (Debian 11).

## Uninstall

`./uninstall.sh` removes the includes and `useConfigOnly`, and removes the
projects directories only while they are empty. Your repositories, your
identity files and your global `[user]` section stay.
