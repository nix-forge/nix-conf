{
  config,
  inputs,
  lib,
  pkgs,
  system,
  ...
}:
let
  cfg = config.programs.helium;
  inherit (import ../../shared/helium-extensions.nix) extensionUpdateUrl heliumExtensions;
  extensionIds = builtins.attrValues heliumExtensions;
  isLinux = builtins.elem system [
    "x86_64-linux"
    "aarch64-linux"
  ];
  isDarwin = builtins.elem system [
    "x86_64-darwin"
    "aarch64-darwin"
  ];

  flagArgs = lib.concatMapStringsSep " \\\n      " (
    flag: "--add-flags ${lib.escapeShellArg flag}"
  ) cfg.flags;

  darwinCrxToZip = pkgs.writeText "helium-crx-to-zip.py" ''
    import pathlib
    import struct
    import sys

    crx = pathlib.Path(sys.argv[1]).read_bytes()
    if crx[:4] != b"Cr24":
        raise SystemExit("not a CRX file")

    version = struct.unpack("<I", crx[4:8])[0]
    if version == 2:
        public_key_len, signature_len = struct.unpack("<II", crx[8:16])
        offset = 16 + public_key_len + signature_len
    elif version == 3:
        header_len = struct.unpack("<I", crx[8:12])[0]
        offset = 12 + header_len
    else:
        raise SystemExit(f"unsupported CRX version: {version}")

    pathlib.Path(sys.argv[2]).write_bytes(crx[offset:])
  '';

  # Helium stores its UI preferences in the Chromium profile. Seed these once
  # before the browser starts, so later changes made in Helium's Settings UI
  # remain user-controlled.
  darwinHeliumPreferenceDefaults = pkgs.writeText "helium-preference-defaults.py" ''
    import json
    import os
    import pathlib
    import tempfile

    preferences_path = pathlib.Path.home() / "Library/Application Support/net.imput.helium/Default/Preferences"
    applied_version = 5

    try:
        preferences = json.loads(preferences_path.read_text())
    except (FileNotFoundError, json.JSONDecodeError):
        preferences = {}

    helium_preferences = preferences.setdefault("helium", {})
    if helium_preferences.get("nix_default_preferences_version", 0) < applied_version:
        browser_preferences = helium_preferences.setdefault("browser", {})
        browser_preferences.update({
            "layout": 2,
            "rounded_frame": True,
            # Shown as "Frameless mode" in current Helium releases.
            "zen_mode": True,
        })

        # These are Helium's optional keyboard shortcuts. Keep them enabled;
        # the New Tab shortcut tiles below are a separate setting.
        helium_preferences.setdefault("settings", {}).setdefault("a11y", {})[
            "copy_page_url_shortcut"
        ] = True
        helium_preferences["settings"].setdefault("behavior", {})[
            "vertical_collapse_shortcut"
        ] = True

        # Hide both personal and enterprise shortcut tiles on the New Tab
        # page (the "Show shortcuts" control in Customize Helium).
        preferences.setdefault("ntp", {}).update({
            "personal_shortcuts_visible": False,
            "enterprise_shortcuts_visible": False,
        })

        # Helium implements vertical-tab collapse through its Cmd+S command.
        # Move that command to Cmd+Option+S, leaving Cmd+S available to sites.
        browser_preferences.setdefault("custom_accelerators", {})["34090"] = {
            "added": ["Alt+Meta+KeyS"],
            "removed": ["Meta+KeyS"],
        }

        # Bitwarden's suggested Cmd+Shift+L clashes with Helium's location-bar
        # shortcut. Use Cmd+Option+Shift+L for autofill instead.
        extension_commands = preferences.setdefault("extensions", {}).setdefault(
            "commands", {}
        )
        extension_commands.pop("mac:Command+Shift+L", None)
        extension_commands["mac:Command+Alt+Shift+L"] = {
            "command_name": "autofill_login",
            "extension": "nngceckbapebfimnlniiiahkandclblb",
            "global": False,
        }
        helium_preferences["nix_default_preferences_version"] = applied_version

        preferences_path.parent.mkdir(parents=True, exist_ok=True)
        file_descriptor, temporary_path = tempfile.mkstemp(
            dir=preferences_path.parent,
            prefix="Preferences.nix-",
        )
        try:
            with os.fdopen(file_descriptor, "w") as temporary_file:
                json.dump(preferences, temporary_file, separators=(",", ":"))
                temporary_file.flush()
                os.fsync(temporary_file.fileno())
            os.replace(temporary_path, preferences_path)
        finally:
            if os.path.exists(temporary_path):
                os.unlink(temporary_path)
  '';

  darwinHeliumPreferenceHook = pkgs.writeText "helium-preference-hook" ''
    ${lib.getExe pkgs.python3} ${darwinHeliumPreferenceDefaults}
  '';

  # macOS treats unmanaged Chromium policy plist files as "Recommended".
  # Recommended policy cannot force-install extensions, so refresh and load the
  # registry at each Helium start instead. A failed refresh deliberately leaves
  # the previous unpacked extension in place for offline starts. Network timeouts
  # ensure a stalled Web Store request cannot leave Helium waiting indefinitely.
  darwinExtensionUpdateHook = pkgs.writeText "helium-extension-update-hook" ''
    extension_root="$HOME/Library/Application Support/net.imput.helium/nix-managed-extensions"
    extension_dirs=""
    ${lib.getExe' pkgs.coreutils "mkdir"} -p "$extension_root"

    ${lib.concatMapStringsSep "\n" (extensionId: ''
      extension_id=${lib.escapeShellArg extensionId}
      extension_dir="$extension_root/$extension_id"
      if [ -d "$extension_dir" ]; then
        extension_dirs="''${extension_dirs:+''${extension_dirs},}$extension_dir"
      fi
    '') extensionIds}

    (
      update_lock="$extension_root/.update-lock"
      if ! ${lib.getExe' pkgs.coreutils "mkdir"} "$update_lock" 2>/dev/null; then
        exit 0
      fi
      trap '${lib.getExe' pkgs.coreutils "rmdir"} "$update_lock"' EXIT

    ${lib.concatMapStringsSep "\n" (extensionId: ''
      extension_id=${lib.escapeShellArg extensionId}
      extension_dir="$extension_root/$extension_id"
      temporary_dir="$(${lib.getExe' pkgs.coreutils "mktemp"} -d "$extension_root/.''${extension_id}.XXXXXX")"

      if [ -n "$temporary_dir" ]; then
        if ${lib.getExe pkgs.curl} --fail --location --retry 0 --connect-timeout 3 --max-time 8 --silent --show-error \
          --output "$temporary_dir/extension.crx" \
          "${extensionUpdateUrl}?response=redirect&acceptformat=crx2,crx3&prodversion=9999.0.0.0&x=id%3D''${extension_id}%26installsource%3Dondemand%26uc" \
          && ${lib.getExe pkgs.python3} ${darwinCrxToZip} "$temporary_dir/extension.crx" "$temporary_dir/extension.zip"; then
          if ${lib.getExe pkgs.unzip} -q "$temporary_dir/extension.zip" -d "$temporary_dir/unpacked" \
            && [ -f "$temporary_dir/unpacked/manifest.json" ]; then
            ${lib.getExe' pkgs.coreutils "rm"} -rf "$extension_dir.next"
            ${lib.getExe' pkgs.coreutils "mv"} "$temporary_dir/unpacked" "$extension_dir.next"
            ${lib.getExe' pkgs.coreutils "rm"} -rf "$extension_dir"
            ${lib.getExe' pkgs.coreutils "mv"} "$extension_dir.next" "$extension_dir"
          fi
        fi

        ${lib.getExe' pkgs.coreutils "rm"} -rf "$temporary_dir"
      fi

      if [ -d "$extension_dir" ]; then
        extension_dirs="''${extension_dirs:+''${extension_dirs},}$extension_dir"
      fi
    '') extensionIds}
    ) >/dev/null 2>&1 &

    if [ -n "$extension_dirs" ]; then
      set -- "--load-extension=$extension_dirs" "$@"
    fi
  '';

  darwinPackageWithFlags =
    if cfg.flags == [ ] then
      cfg.package
    else
      cfg.package.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ];
        postInstall = (old.postInstall or "") + ''
          heliumApp="$out/Applications/Helium.app"
          heliumExe="$heliumApp/Contents/MacOS/Helium"

          if [ -x "$heliumExe" ] && [ ! -e "$heliumExe-unwrapped" ]; then
            mv "$heliumExe" "$heliumExe-unwrapped"
            makeWrapper "$heliumExe-unwrapped" "$heliumExe" \
              ${flagArgs} \
              --run ${lib.escapeShellArg "source ${darwinHeliumPreferenceHook}; source ${darwinExtensionUpdateHook}"}

            rm -f "$out/bin/helium"
            makeWrapper "$heliumExe-unwrapped" "$out/bin/helium" \
              ${flagArgs} \
              --run ${lib.escapeShellArg "source ${darwinHeliumPreferenceHook}; source ${darwinExtensionUpdateHook}"}
          fi
        '';
      });
in
{
  imports = [ ./flags.nix ] ++ lib.optionals isLinux [ inputs.helium-browser.homeModules.default ];
}
// lib.optionalAttrs isDarwin {
  options.programs.helium = {
    enable = lib.mkEnableOption "Helium Browser";

    package = lib.mkOption {
      type = lib.types.package;
      default = inputs.helium-browser-darwin.packages.${system}.default;
      defaultText = "inputs.helium-browser-darwin.packages.\${system}.default";
      description = "The Helium package to use.";
    };

    flags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      example = [
        "--no-first-run"
        "--no-default-browser-check"
      ];
      description = "Additional command-line flags passed to Helium.";
    };
  };

  config = lib.mkMerge [
    { programs.helium.enable = true; }
    (lib.mkIf cfg.enable { home.packages = [ darwinPackageWithFlags ]; })
  ];
}
// lib.optionalAttrs isLinux {
  config = {
    programs.helium.enable = true;
  };
}
