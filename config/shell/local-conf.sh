# shellcheck shell=sh disable=SC3043
# Read machine-local settings from ${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local.conf.
# The file is read, never executed: only NAME=value lines count (an
# "export " prefix is allowed), and the last one wins. An environment
# variable of the same name wins over the file. A trailing " # comment"
# and one level of quotes are removed. POSIX sh; also works in bash 3.2,
# dash, busybox ash and zsh. SC3043: every one of them has `local`.
# Example: config/dotfiles/local.conf.example.

# Sets _dotfiles_conf to the value of setting $1 and returns 0, or returns
# 1 when it is set neither in the environment nor in the file.
_dotfiles_conf_get() {
  local name="$1" conf line value found=""
  eval "found=\${$name+x}"
  if [ -n "$found" ]; then
    eval "value=\${$name}"
  else
    conf="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/local.conf"
    [ -r "$conf" ] || return 1
    while IFS= read -r line || [ -n "$line" ]; do
      line=${line#export }
      case $line in
        "$name="*) value=${line#*=} found=x ;;
      esac
    done <"$conf"
    [ -n "$found" ] || return 1
  fi
  value=${value%%[[:space:]]#*}
  value=${value%"${value##*[![:space:]]}"}
  value=${value#[\"\']} value=${value%[\"\']}
  _dotfiles_conf=$value
}
