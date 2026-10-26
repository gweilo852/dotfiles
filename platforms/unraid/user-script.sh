#!/bin/bash
# Relink the dotfiles after an Unraid reboot.
#
# Unraid rebuilds /root from RAM at every boot, so the links that
# install.sh makes disappear. To restore them automatically, add this
# script to the User Scripts plugin with the schedule "At Startup of Array".
# Set DOTFILES_DIR to your clone first. This script changes only files in
# /root, and it does not touch /boot.
DOTFILES_DIR=/mnt/user/appdata/dotfiles

if [ -x "$DOTFILES_DIR/install.sh" ]; then
  HOME=/root "$DOTFILES_DIR/install.sh" --unraid --yes --skip-validate
fi
