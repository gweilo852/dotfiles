#!/usr/bin/env bash
# Install the managed terminal configuration. Safe to run more than once.
# Run ./install.sh --help for options.
set -euo pipefail

DOTFILES_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$DOTFILES_DIR/scripts/lib.sh"

usage() {
  cat <<'EOF'
Usage: ./install.sh [options]

  -n, --dry-run          Show what would change. Change nothing.
  -y, --yes              Do not ask for confirmation.
      --no-packages      Do not install packages. Only link configuration.
      --release-binaries Install missing tools from pinned, checksum-verified
                         GitHub release archives into a user bin directory
                         (Linux, WSL and Unraid only).
      --windows-wezterm  WSL only: copy the WezTerm config to the Windows
                         user profile (%USERPROFILE%\.wezterm.lua).
      --unraid           Required on Unraid. Selects the minimal Unraid mode.
      --interactive-zsh  Start zsh from interactive bash and in new tmux
                         windows, for an account whose login shell must stay
                         bash (Active Directory). Sets
                         DOTFILES_INTERACTIVE_ZSH=1 in
                         ~/.config/dotfiles/local.conf. Not on Unraid.
      --no-interactive-zsh
                         Remove that setting again (back up first).
      --repos            Projects layout and Git identities: create
                         ~/projects/{personal,work,scratch} (never moves or
                         clones), and include a per-scope identity file
                         for repositories under personal/ and work/.
      --ai               Shared and local instructions for coding agents:
                         adapters for Claude Code, Codex and Gemini CLI
                         (only those present). Never installs a provider.
      --skip-validate    Do not run the validation step.
  -h, --help             Show this help.
EOF
}

ORIG_ARGS=("$@")
NO_PACKAGES=0 RELEASE_BINARIES=0 WINDOWS_WEZTERM=0 UNRAID_OK=0 VALIDATE=1
INTERACTIVE_ZSH="" # 1 = turn on, 0 = turn off, empty = leave as it is
REPOS=0 AI=0
while [ $# -gt 0 ]; do
  case "$1" in
    -n | --dry-run) DRY_RUN=1 ;;
    -y | --yes) ASSUME_YES=1 ;;
    --no-packages) NO_PACKAGES=1 ;;
    --release-binaries) RELEASE_BINARIES=1 ;;
    --windows-wezterm) WINDOWS_WEZTERM=1 ;;
    --unraid) UNRAID_OK=1 ;;
    --interactive-zsh) INTERACTIVE_ZSH=1 ;;
    --no-interactive-zsh) INTERACTIVE_ZSH=0 ;;
    --repos) REPOS=1 ;;
    --ai) AI=1 ;;
    --skip-validate) VALIDATE=0 ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown option: $1" ;;
  esac
  shift
done
export DRY_RUN ASSUME_YES DOTFILES_DIR TIMESTAMP

PLATFORM=$(detect_platform)
init_state_paths "$PLATFORM"
export DOTFILES_PLATFORM_DETECTED=$PLATFORM

info "dotfiles: $DOTFILES_DIR"
info "platform: $PLATFORM$([ "$DRY_RUN" = 1 ] && echo ' (dry run)')"
info "system:   $(detect_distro)"

# --------------------------------------------------------------------
# Safety gates
# --------------------------------------------------------------------

case "$PLATFORM" in
  unraid)
    if [ "$UNRAID_OK" != 1 ]; then
      die "Unraid detected. Unraid mode must be selected explicitly: ./install.sh --unraid
See docs/installation.md#unraid before you continue."
    fi
    [ "$INTERACTIVE_ZSH" = 1 ] && die "--interactive-zsh is not available on Unraid; Unraid uses bash"
    # $HOME and / live in RAM on Unraid, and /boot is FAT32 (no symlinks).
    case "$DOTFILES_DIR" in
      /mnt/*) ;;
      *) die "On Unraid the repository must live on persistent storage under /mnt
(for example /mnt/user/appdata/dotfiles). Current location: $DOTFILES_DIR" ;;
    esac
    NO_PACKAGES=1
    ;;
  unknown) die "unsupported platform: $DOTFILES_UNAME" ;;
  *)
    [ "$UNRAID_OK" = 1 ] && die "--unraid was given, but this machine is not Unraid"
    ;;
esac
[ "$WINDOWS_WEZTERM" = 1 ] && [ "$PLATFORM" != wsl ] && die "--windows-wezterm works only on WSL"
[ "$RELEASE_BINARIES" = 1 ] && [ "$PLATFORM" = macos ] && die "--release-binaries is for Linux; use Homebrew on macOS"

# Show the plan and ask before the first real change.
if [ "$DRY_RUN" != 1 ] && [ "$ASSUME_YES" != 1 ]; then
  [ -t 0 ] || die "not interactive: run with --dry-run to preview, then --yes to apply"
  "$DOTFILES_DIR/install.sh" --dry-run "${ORIG_ARGS[@]}"
  echo
  confirm "Apply these changes?" || die "cancelled; nothing changed"
  echo
fi

# --------------------------------------------------------------------
# Prerequisites and packages
# --------------------------------------------------------------------

info "prerequisites"
for tool in git curl; do
  if has "$tool"; then ok "$tool"; else warn "$tool not found"; fi
done

if [ "$NO_PACKAGES" = 1 ]; then
  info "packages: skipped"
else
  info "packages"
  case "$PLATFORM" in
    macos) "$DOTFILES_DIR/scripts/bootstrap-macos.sh" || warn "package installation incomplete; continuing" ;;
    linux | wsl) "$DOTFILES_DIR/scripts/bootstrap-linux.sh" || warn "package installation incomplete; continuing" ;;
  esac
fi

if [ "$RELEASE_BINARIES" = 1 ]; then
  info "release binaries"
  if [ "$PLATFORM" = unraid ]; then
    BIN_DIR="$DOTFILES_DIR/.local/bin" "$DOTFILES_DIR/scripts/install-release-binaries.sh"
  else
    BIN_DIR="$HOME/.local/bin" "$DOTFILES_DIR/scripts/install-release-binaries.sh"
  fi
fi

# --------------------------------------------------------------------
# Configuration
# --------------------------------------------------------------------

info "configuration"
C="$DOTFILES_DIR/config"

# zsh configuration only where zsh exists; bash is configured everywhere.
if has zsh; then
  link_file "$C/zsh/zshrc" "$HOME/.zshrc"
  migrate_zshrc "${LAST_BACKUP:-}"
  # Ubuntu (and ID_LIKE=ubuntu) /etc/zsh/zshrc runs its own compinit,
  # without -i, unless ~/.zshenv sets skip_global_compinit. That is a second
  # compinit, and it prompts or aborts on insecure directories. The same
  # condition as in that file; Debian and others are not affected.
  if grep -qs skip_global_compinit "$DOTFILES_SYSROOT/etc/zsh/zshrc" &&
    grep -qsE '^ID(_LIKE)?=.*ubuntu' "$DOTFILES_SYSROOT/etc/os-release"; then
    ensure_block "$HOME/.zshenv" zshenv "skip_global_compinit=1 # compinit runs once, in the managed ~/.zshrc"
  fi
else
  info "  zsh not installed: zsh configuration skipped (bash is configured)"
fi

link_file "$C/starship/starship.toml" "${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
link_file "$C/tmux/tmux.conf" "$HOME/.tmux.conf"

# WezTerm runs on the machine you type on. A headless Linux host (a VDI
# reached over SSH) does not need its config.
if [ "$PLATFORM" = macos ] || { [ "$PLATFORM" = linux ] && has wezterm; }; then
  link_file "$C/wezterm/wezterm.lua" "${XDG_CONFIG_HOME:-$HOME/.config}/wezterm/wezterm.lua"
fi

# Bash keeps the distribution's own ~/.bashrc and only adds a source line.
ensure_block "$HOME/.bashrc" bash "[ -r \"$C/bash/bashrc\" ] && . \"$C/bash/bashrc\""

# A bash login shell (SSH) reads one profile file and not ~/.bashrc. Most
# distributions' ~/.profile already loads ~/.bashrc; if the file that bash
# reads does not, add a block. The guard keeps sh and dash out, because
# they also read ~/.profile. With --interactive-zsh and no profile file at
# all, create ~/.profile, because the handoff starts from ~/.bashrc.
login_file=$(bash_login_file)
if [ -z "$login_file" ] && [ "$INTERACTIVE_ZSH" = 1 ]; then
  login_file="$HOME/.profile"
fi
if [ -n "$login_file" ] && ! grep -q 'bashrc' "$login_file" 2>/dev/null; then
  ensure_block "$login_file" bash_profile \
    "case \$- in *i*) [ -n \"\${BASH_VERSION:-}\" ] && [ -r \"\$HOME/.bashrc\" ] && . \"\$HOME/.bashrc\" ;; esac"
fi

# Interactive zsh handoff: a machine-local setting, in a marked block.
case "$INTERACTIVE_ZSH" in
  1)
    has zsh || warn "zsh not found; the handoff stays inactive until zsh is on PATH or DOTFILES_ZSH is set"
    ensure_block "$LOCAL_CONF" interactive-zsh "# Interactive bash and new tmux windows start zsh. The login shell stays.
# Turn off: ./install.sh --no-interactive-zsh (docs/active-directory.md)
DOTFILES_INTERACTIVE_ZSH=1"
    ;;
  0)
    if [ -f "$LOCAL_CONF" ] && grep -qF "$(block_begin interactive-zsh)" "$LOCAL_CONF"; then
      backup=$(backup_path "$LOCAL_CONF" copy) || die "cannot back up $LOCAL_CONF"
      change "back up $LOCAL_CONF -> $backup"
      [ "$DRY_RUN" = 1 ] || remove_block "$LOCAL_CONF" interactive-zsh
      change "remove interactive-zsh block from $LOCAL_CONF"
    else
      ok "interactive zsh handoff: no managed setting in $LOCAL_CONF"
    fi
    outside=$(awk -v b="$(block_begin interactive-zsh)" -v e="$(block_end interactive-zsh)" '
      $0 == b { s = 1; next } $0 == e { s = 0; next }
      !s && /^[[:space:]]*(export[[:space:]]+)?DOTFILES_INTERACTIVE_ZSH=/ { print NR }
    ' "$LOCAL_CONF" 2>/dev/null | paste -sd, -)
    [ -z "$outside" ] || warn "$LOCAL_CONF line(s) $outside set DOTFILES_INTERACTIVE_ZSH outside the managed block; edit them by hand"
    ;;
esac

# Add include.path $1 to ~/.gitconfig once (backup, manifest). A file that
# this run created is not backed up again.
GITCONFIG_CREATED=""
ensure_gitinclude() {
  local backup=""
  if git config --global --get-all include.path 2>/dev/null | grep -qxF "$1"; then
    ok "git include $1"
    return 0
  fi
  [ -e "$HOME/.gitconfig" ] || GITCONFIG_CREATED=1
  if [ -f "$HOME/.gitconfig" ] && [ -z "$GITCONFIG_CREATED" ]; then
    backup=$(backup_path "$HOME/.gitconfig" copy) || die "cannot back up ~/.gitconfig"
    change "back up $HOME/.gitconfig -> $backup"
  fi
  run git config --global --add include.path "$1"
  change "add include.path $1 to ~/.gitconfig"
  manifest_add gitinclude "$HOME/.gitconfig" "$1" "$backup"
}

# Add the global git value $2 to key $1 once (multi-valued, like
# --add), with a backup and a manifest entry.
ensure_gitconfig() {
  local backup=""
  if git config --global --get-all "$1" 2>/dev/null | grep -qxF "$2"; then
    ok "git $1 = $2"
    return 0
  fi
  [ -e "$HOME/.gitconfig" ] || GITCONFIG_CREATED=1
  if [ -f "$HOME/.gitconfig" ] && [ -z "$GITCONFIG_CREATED" ]; then
    backup=$(backup_path "$HOME/.gitconfig" copy) || die "cannot back up ~/.gitconfig"
    change "back up $HOME/.gitconfig -> $backup"
  fi
  run git config --global --add "$1" "$2"
  change "add $1 = $2 to ~/.gitconfig"
  manifest_add gitconfig "$HOME/.gitconfig" "$1=$2" "$backup"
}

# Create directory $1 when it is missing (manifest: uninstall removes it
# only while it is empty).
ensure_dir() {
  if [ -d "$1" ]; then
    ok "$1"
    return 0
  fi
  run mkdir -p "$1"
  change "create directory $1"
  manifest_add dir "$1" "" ""
}

if has git; then
  ensure_gitinclude "$C/git/config"
  # zdiff3 needs git 2.35; older git (Debian 11: 2.30.2) stops every
  # command that reads it ("unknown style 'zdiff3'"). The shared file uses
  # diff3; this include, after it, upgrades to zdiff3 where git allows.
  if git_version_ge 2 35; then
    ensure_gitinclude "$C/git/zdiff3.config"
  elif git config --global --get-all include.path 2>/dev/null | grep -qxF "$C/git/zdiff3.config"; then
    backup=$(backup_path "$HOME/.gitconfig" copy) || die "cannot back up ~/.gitconfig"
    change "back up $HOME/.gitconfig -> $backup"
    run git config --global --unset-all include.path "^$(printf '%s' "$C/git/zdiff3.config" | sed 's/[][\\.*^$/]/\\&/g')\$"
    change "remove include.path $C/git/zdiff3.config (git $(git --version | cut -d' ' -f3) is older than 2.35)"
  fi
else
  warn "git not found; git settings skipped"
fi

# Projects layout and Git identity separation (docs/repositories.md).
if [ "$REPOS" = 1 ]; then
  info "projects and git identities"
  # shellcheck source=config/shell/local-conf.sh
  . "$C/shell/local-conf.sh"
  PROJECTS="$HOME/projects"
  if _dotfiles_conf_get DOTFILES_PROJECTS; then PROJECTS=$_dotfiles_conf; fi
  case $PROJECTS in "~"/*) PROJECTS="$HOME/${PROJECTS#\~/}" ;; esac
  PROJECTS=${PROJECTS%/}
  for d in "$PROJECTS" "$PROJECTS/personal" "$PROJECTS/work" "$PROJECTS/scratch"; do
    ensure_dir "$d"
  done
  if has git; then
    IDDIR="${XDG_CONFIG_HOME:-$HOME/.config}/git"
    # Only identities from configuration; no guess from the host name.
    if [ -z "$(git config --global --get user.useConfigOnly 2>/dev/null)" ]; then
      ensure_gitconfig user.useConfigOnly true
    elif [ "$(git config --global --get user.useConfigOnly)" != true ]; then
      warn "user.useConfigOnly is set to $(git config --global --get user.useConfigOnly) in ~/.gitconfig; left unchanged"
    fi
    # Git matches gitdir: against the git directory and its physical path,
    # but not against a resolved pattern. A worktree's git directory is a
    # physical path, so a root behind a symlink needs both patterns.
    PROJECTS_REAL=$( (cd "$PROJECTS" 2>/dev/null && pwd -P) || echo "$PROJECTS")
    for scope in personal work; do
      # The guard first, then the scope's own identity (later wins). The
      # gitdir match also covers worktrees: their git directory is inside
      # the main repository.
      ensure_gitconfig "includeIf.gitdir:$PROJECTS/$scope/.path" "$C/git/identity-guard.config"
      ensure_gitconfig "includeIf.gitdir:$PROJECTS/$scope/.path" "$IDDIR/identity-$scope"
      if [ "$PROJECTS_REAL" != "$PROJECTS" ]; then
        ensure_gitconfig "includeIf.gitdir:$PROJECTS_REAL/$scope/.path" "$C/git/identity-guard.config"
        ensure_gitconfig "includeIf.gitdir:$PROJECTS_REAL/$scope/.path" "$IDDIR/identity-$scope"
      fi
      if [ -f "$IDDIR/identity-$scope" ]; then
        ok "identity for $scope: $IDDIR/identity-$scope"
      else
        info "  no $scope identity yet; commits under $PROJECTS/$scope/ stop until you create it:"
        echo "      mkdir -p $IDDIR"
        echo "      git config --file $IDDIR/identity-$scope user.name \"Your Name\""
        echo "      git config --file $IDDIR/identity-$scope user.email \"you@$scope.example\""
      fi
    done
  fi
fi

# Instructions for coding agents (docs/ai.md). AGENTS.md is the canonical
# format; each provider gets an adapter in the form it reads.
if [ "$AI" = 1 ]; then
  info "AI instructions"
  AI_HOME="${XDG_CONFIG_HOME:-$HOME/.config}/ai"
  AI_OUT="$STATE_DIR/ai"
  if [ -e "$AI_HOME/AGENTS.md" ]; then
    ok "$AI_HOME/AGENTS.md (yours; not changed)"
  else
    make_parents "$AI_HOME/AGENTS.md"
    run cp "$C/ai/AGENTS.local.example.md" "$AI_HOME/AGENTS.md"
    change "create $AI_HOME/AGENTS.md from the example (yours from now on)"
  fi
  new_generated=""
  for f in scope-personal.md scope-work.md AGENTS.md; do
    [ -e "$AI_OUT/$f" ] || new_generated="$new_generated $f"
  done
  DRY_RUN=$DRY_RUN "$DOTFILES_DIR/scripts/ai-sync.sh" || warn "scripts/ai-sync.sh failed"
  for f in $new_generated; do
    [ -e "$AI_OUT/$f" ] && manifest_add generated "$AI_OUT/$f" "" ""
  done
  # Claude Code and Gemini CLI: imports, so they always read the sources.
  ai_block="<!-- Shared and local instructions for coding agents (dotfiles: docs/ai.md). -->
@$C/ai/AGENTS.md
@$AI_HOME/AGENTS.md
@$AI_OUT/scope-personal.md
@$AI_OUT/scope-work.md"
  CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
  if has claude || [ -d "$CLAUDE_DIR" ]; then
    ensure_block "$CLAUDE_DIR/CLAUDE.md" ai-md "$ai_block"
  else
    info "  Claude Code not found: skipped (run install.sh --ai again after you install it)"
  fi
  if has gemini || [ -d "$HOME/.gemini" ]; then
    ensure_block "$HOME/.gemini/GEMINI.md" ai-md "$ai_block"
  else
    info "  Gemini CLI not found: skipped"
  fi
  # Codex: no imports, so a link to the generated bundle. An existing
  # global AGENTS.md is yours and is not replaced.
  CODEX_DIR="${CODEX_HOME:-$HOME/.codex}"
  if has codex || [ -d "$CODEX_DIR" ]; then
    if [ -L "$CODEX_DIR/AGENTS.md" ] && [ "$(readlink "$CODEX_DIR/AGENTS.md")" = "$AI_OUT/AGENTS.md" ]; then
      ok "$CODEX_DIR/AGENTS.md"
    elif [ -e "$CODEX_DIR/AGENTS.md" ] || [ -L "$CODEX_DIR/AGENTS.md" ]; then
      warn "$CODEX_DIR/AGENTS.md is yours; not changed. To use the shared instructions, move its text to $AI_HOME/AGENTS.md and remove it, then run install.sh --ai again"
    else
      link_file "$AI_OUT/AGENTS.md" "$CODEX_DIR/AGENTS.md"
    fi
  else
    info "  Codex not found: skipped"
  fi
fi

if [ "$WINDOWS_WEZTERM" = 1 ]; then
  winprofile=$(cmd.exe /c 'echo %USERPROFILE%' 2>/dev/null | tr -d '\r') || true
  [ -n "$winprofile" ] || die "cannot find the Windows user profile"
  winhome=$(wslpath "$winprofile")
  copy_file "$C/wezterm/wezterm.lua" "$winhome/.wezterm.lua"
  [ -e "$winhome/.config/wezterm/wezterm.lua" ] &&
    warn "$winhome/.config/wezterm/wezterm.lua also exists; WezTerm reads ~/.wezterm.lua first"
fi

# --------------------------------------------------------------------
# Validation and summary
# --------------------------------------------------------------------

if [ "$DRY_RUN" != 1 ] && [ "$VALIDATE" = 1 ]; then
  info "validation"
  "$DOTFILES_DIR/scripts/doctor.sh" --quick || WARNINGS=$((WARNINGS + 1))
fi

echo
if [ "$DRY_RUN" = 1 ]; then
  info "dry run: $CHANGES change(s) planned, $WARNINGS warning(s). Nothing changed."
else
  info "done: $CHANGES change(s), $WARNINGS warning(s)"
  [ -d "$BACKUP_DIR" ] && echo "  backups:  $BACKUP_DIR"
  echo "  manifest: $MANIFEST"
  echo "  local settings (never managed): ~/.zshrc.local, ~/.config/wezterm/wezterm_local.lua"
  # shellcheck source=config/shell/local-conf.sh
  . "$C/shell/local-conf.sh"
  # shellcheck source=config/shell/zsh-handoff.sh
  . "$C/shell/zsh-handoff.sh"
  if _dotfiles_zsh_handoff_target; then
    echo "  interactive zsh handoff: on ($_dotfiles_zsh). Log in again; \$SHELL still shows bash."
  else
    echo "  interactive zsh handoff: $_dotfiles_zsh_why"
  fi
  echo "  start a new shell to load the configuration: exec \$SHELL -l"
  if [ "$PLATFORM" = unraid ]; then
    echo
    echo "  Unraid: \$HOME resets at boot. To relink at boot, see"
    echo "  $DOTFILES_DIR/platforms/unraid/user-script.sh (nothing was added to /boot)."
  fi
fi
