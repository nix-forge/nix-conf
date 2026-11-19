let
  policy = builtins.fromJSON (builtins.readFile ./build-policy.json);
in
assert (policy.desktop.host or null) == "desktop";
policy
