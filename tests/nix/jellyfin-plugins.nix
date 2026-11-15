# Validate the actual desktop server/plugins without forcing its toplevel assertions.
{
  pkgs,
  desktop,
  introChecker,
}:
let
  inherit (pkgs) lib;
  python = pkgs.python3.withPackages (packages: [ packages.pytest ]);
  service = desktop.config.services.jellyfin;
  selected = desktop.config.homelab.optional.jellyfinPlugins.packages;
  keys = [
    "Intro Skipper_nix"
    "Subtitle Extract_nix"
    "Moonfin_nix"
  ];
  plugins = pkgs.writeText "configured-jellyfin-plugins.json" (
    builtins.toJSON (
      lib.genAttrs keys (key: {
        output = toString selected.${key};
        version = selected.${key}.version;
      })
    )
  );
  checker = builtins.path {
    path = ../jellyfin/plugin_compatibility.py;
    name = "jellyfin-plugin-compatibility.py";
  };
  contract = builtins.path {
    path = ../jellyfin/test_plugin_compatibility.py;
    name = "test-jellyfin-plugin-compatibility.py";
  };
  maintainedIntroChecker = builtins.path {
    path = introChecker;
    name = "jellyfin-intro-checker.py";
  };
in
assert service.enable;
assert
  builtins.sort builtins.lessThan (builtins.attrNames selected)
  == builtins.sort builtins.lessThan keys;
assert pkgs.stdenv.hostPlatform.system == desktop.pkgs.stdenv.hostPlatform.system;
pkgs.runCommand "configured-jellyfin-plugin-compatibility"
  {
    nativeBuildInputs = [
      python
      desktop.pkgs.jellyfin-ffmpeg
    ];
    __noChroot = false;
    meta.platforms = [ "x86_64-linux" ];
  }
  ''
    mkdir -p "$out"
    mkdir jellyfin
    cp ${checker} jellyfin/plugin_compatibility.py
    JELLYFIN_INTRO_CHECKER=${maintainedIntroChecker} PYTHONPATH="$PWD" \
      PYTEST_DISABLE_PLUGIN_AUTOLOAD=1 python3 -m pytest ${contract} -q -p no:cacheprovider \
        --import-mode=importlib -o addopts= \
        -o "markers=nix_integration: generated artifacts supplied by this Nix check"
    python3 ${checker} \
      --intro-checker ${maintainedIntroChecker} \
      --server ${lib.getExe service.package} \
      --server-version ${lib.escapeShellArg service.package.version} \
      --plugins ${plugins} \
      --output "$out/compatibility.json"
  ''
