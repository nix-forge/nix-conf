# Serialize an argv list for systemd Exec directives. Quoting alone does not
# suppress systemd's dollar-variable and percent-specifier expansion.
arguments:
builtins.concatStringsSep " " (
  map (
    argument: builtins.replaceStrings [ "%" "$" ] [ "%%" "$$" ] (builtins.toJSON (toString argument))
  ) arguments
)
