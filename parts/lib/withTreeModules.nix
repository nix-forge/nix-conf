modules: builtins.map (x: if x ? "default" then x.default else x) modules
