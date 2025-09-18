modules: builtins.map (x: if builtins.hasAttr "default" x then x.default else x) modules
