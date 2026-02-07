modules:
builtins.map (
  x: if (builtins.typeOf x == "set" && builtins.hasAttr "default" x) then x.default else x
) modules
