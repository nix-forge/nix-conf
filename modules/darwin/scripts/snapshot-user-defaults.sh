# shellcheck shell=bash
# Nix builder/activation callers and rendered fragments provide external variables.
# shellcheck disable=SC2034
finder_animation_before="$(@readUserDefault_com_apple_finder_DisableAllAnimations@)"
passwords_menu_before="$(@readUserDefault_com_apple_Passwords_EnableMenuBarExtra@)"
siri_menu_before="$(@readUserDefault_com_apple_Siri_StatusMenuVisible@)"
spotlight_menu_before="$(@readCurrentHostUserDefault_com_apple_Spotlight_MenuItemHidde@)"
