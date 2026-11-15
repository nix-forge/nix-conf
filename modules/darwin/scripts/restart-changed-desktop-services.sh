# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2154
finder_animation_after="$(@readUserDefault_com_apple_finder_DisableAllAnimations@)"
if [ "$finder_animation_before" != "$finder_animation_after" ]; then
  echo >&2 "restarting Finder after changing its animation policy..."
  /usr/bin/killall -qu @user@ Finder || true
fi

siri_menu_after="$(@readUserDefault_com_apple_Siri_StatusMenuVisible@)"
spotlight_menu_after="$(@readCurrentHostUserDefault_com_apple_Spotlight_MenuItemHidde@)"
passwords_menu_after="$(@readUserDefault_com_apple_Passwords_EnableMenuBarExtra@)"
if [ "$passwords_menu_before" != "$passwords_menu_after" ] ||
  [ "$siri_menu_before" != "$siri_menu_after" ] ||
  [ "$spotlight_menu_before" != "$spotlight_menu_after" ]; then
  echo >&2 "restarting SystemUIServer after changing menu bar visibility..."
  /usr/bin/killall -qu @user@ com.apple.Passwords.MenuBarExtra || true
  /usr/bin/killall -qu @user@ SystemUIServer || true
fi
