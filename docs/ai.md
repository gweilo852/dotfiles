# Instructions for coding agents

`AGENTS.md` is the canonical, provider-neutral format. dotfiles keeps one
set of global instructions and gives each provider an adapter in the form
that it reads. No provider is installed by dotfiles.

## Sources

| Level | File | In the repository? |
| --- | --- | --- |
| shared | `config/ai/AGENTS.md` | yes: generic, public text only |
| yours, every machine-wide session | `~/.config/ai/AGENTS.md` | no (created once from `config/ai/AGENTS.local.example.md`) |
| personal or work scope | `~/.config/ai/scopes/personal.md`, `~/.config/ai/scopes/work.md` | no (optional; create them yourself) |
| repository | the repository's own `AGENTS.md` | in that repository |

Employer policies, internal names, private paths and credentials belong in
the local files, never in the dotfiles repository. `scripts/test.sh` scans
the repository for credential patterns and for terms in your private
denylist.

## How each provider reads instructions

Checked against the providers' documentation on 2026-10-27:

| | Claude Code | Codex | Gemini CLI |
| --- | --- | --- | --- |
| Global file | `~/.claude/CLAUDE.md` (`CLAUDE_CONFIG_DIR`) | `~/.codex/AGENTS.md` (`CODEX_HOME`); `AGENTS.override.md` wins | `~/.gemini/GEMINI.md` |
| Imports | `@path`, also absolute and `~`; 4 levels; no prompt in the user file | none | `@path`, relative and absolute |
| Project files | `CLAUDE.md` in the working directory and every parent; `AGENTS.md` only when no `CLAUDE.md` exists there | `AGENTS.md` from the Git root down to the working directory; nothing above the Git root | `GEMINI.md` in workspace directories and parents; `context.fileName` can list `AGENTS.md` |
| Size | not documented | 32 KiB in total by default (`project_doc_max_bytes`) | not documented |

No provider can be relied on to read a file between the projects root and
a repository (for example `~/projects/work/AGENTS.md`): Codex stops at the
Git root, Gemini's limit is not documented, and a `CLAUDE.md` there would
stop Claude Code from reading the repositories' own `AGENTS.md`.

## Adapters (`./install.sh --ai`)

The installer configures each provider that is present: its command is on
PATH or its configuration directory exists. Run it again after you install
a provider.

- **Claude Code**: a marked block at the end of `~/.claude/CLAUDE.md` with
  imports of the shared file, your file and the two scope wrappers. Your
  own text in that file stays (it is backed up first).
- **Gemini CLI**: the same block in `~/.gemini/GEMINI.md`.
- **Codex**: no imports, so `~/.codex/AGENTS.md` becomes a link to a
  generated file that contains everything. If you already have a
  `~/.codex/AGENTS.md`, it is not changed; move its text to
  `~/.config/ai/AGENTS.md` first.

The blocks use HTML-comment markers (`<!-- >>> dotfiles (ai-md) >>> -->`),
because a `#` line would be a heading in the instructions.

## Scope instructions

Scope files reach every provider in the same way: under a heading that says
where they apply, for example:

```text
## Work scope

Apply this section only when the working directory is inside
/home/you/projects/work/ (including worktrees ...). Ignore it elsewhere.
```

Loading is the same for all providers. The agent applies the condition.
Both scopes are in every session's context, so keep them short.

## Keeping the generated files current

`scripts/ai-sync.sh` writes the scope wrappers and the Codex bundle into
the dotfiles state directory (`~/.local/state/dotfiles/ai/`). Claude Code
and Gemini CLI import your files directly, so they see a change at once.
Codex reads the bundle, so run this after you edit an instruction file:

```sh
scripts/ai-sync.sh           # write what changed
scripts/ai-sync.sh --check   # exit 1 when a generated file is stale
```

`scripts/doctor.sh` warns when the generated files are stale, and
`ai-sync.sh` warns when the bundle is larger than Codex's 32 KiB default.

## Repository instructions

Each repository keeps its own `AGENTS.md`. Claude Code reads it only when
no `CLAUDE.md` exists in the working directory or above. Two ways keep it
working for Claude Code (a choice for each repository; dotfiles does not
change repositories):

- a `CLAUDE.md` in the repository that contains `@AGENTS.md`; or
- Claude Code's "Project instructions" setting (`/config`), set to read
  both files.

For Gemini CLI, add `AGENTS.md` to `context.fileName` in
`~/.gemini/settings.json`, for example
`{"context": {"fileName": ["AGENTS.md", "GEMINI.md"]}}`. dotfiles does not
edit that file.

## Uninstall

`./uninstall.sh` removes the blocks (restoring your files exactly), deletes
a `GEMINI.md` that only held the block, removes the Codex link and the
generated files, and keeps your files in `~/.config/ai/`.
