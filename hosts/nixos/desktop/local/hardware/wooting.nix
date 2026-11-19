{ myLib, pkgs, ... }:
let
  writeShellApplication = myLib.writers.writeShellApplication { inherit pkgs; };
  # Native schema 15 export of the restored ANSI typing profile. Keep the
  # requested RGB channel values; device readback can round LED channels.
  profile = builtins.fromJSON (builtins.readFile ./wooting-typing.json);
  # Wootility 5.4.2 wooting-usb/src/layouts/hidCodes.ts defines these profile
  # codes (not USB HID usage numbers). Keep firmware and host modifier swaps
  # mutually exclusive. The right Ctrl position becomes Option; left Ctrl stays.
  modifiers = {
    leftControl = 99;
    leftOption = 101;
    leftCommand = 102;
    rightCommand = 106;
    rightOption = 105;
  };
  workRemaps = [
    {
      column = 0;
      value = modifiers.leftControl;
    }
    {
      column = 1;
      value = modifiers.leftOption;
    }
    {
      column = 2;
      value = modifiers.leftCommand;
    }
    {
      column = 10;
      value = modifiers.rightCommand;
    }
    {
      column = 11;
      value = modifiers.rightOption;
    }
  ];
  # Set both layers, including explicit overrides: holding Fn must never change
  # the meaning of a modifier. Preserve every other native profile field.
  workLayer =
    layer:
    builtins.filter (
      entry: !(entry.index.rowNr == 5 && builtins.any (key: key.column == entry.index.colNr) workRemaps)
    ) layer
    ++ map (key: {
      index = {
        rowNr = 5;
        colNr = key.column;
      };
      inherit (key) value;
    }) workRemaps;
  workProfile = profile // {
    name = "Mac Work";
    desc = "Command beside Space; Control + Option manages windows. See keyboard-workflow.md.";
    remap = map workLayer profile.remap;
  };
  workExport = pkgs.writeText "wooting-mac-work.json" (builtins.toJSON workProfile + "\n");
  publisher =
    (import ../../../../../flake/runtime-packages.nix { inherit pkgs; }).wootingProfileShare;
  # Production input validation: offline, no HOME/state/device/network access.
  # Reject unsupported Nix edits before exposing an apply/publish command.
  validatedWork = pkgs.runCommand "wooting-mac-work-validated.json" { } ''
    ${pkgs.lib.getExe publisher} validate --profile ${workExport}
    ln -s ${workExport} "$out"
  '';
  shareWork = writeShellApplication {
    name = "wooting-mac-work";
    text = ''
      exec ${pkgs.lib.getExe publisher} "$@" --profile ${validatedWork}
    '';
  };
  exports = pkgs.linkFarm "wooting-80he-profiles" [
    {
      name = "01-typing.json";
      path = pkgs.writeText "wooting-typing.json" (builtins.toJSON profile + "\n");
    }
    {
      name = "02-mac-work.json";
      path = validatedWork;
    }
    {
      name = "bin";
      path = "${shareWork}/bin";
    }
    {
      name = "README.md";
      path = ./wooting-profile-readme.md;
    }
    {
      name = "layout.html";
      path = ../../../../../docs/assets/keyboard/wooting-layout.html;
    }
  ];
in
{
  # Activation installs the export; Wootility owns deliberate onboard writes.
  environment.etc."wooting/profiles".source = exports;
  system.build.wootingProfiles = exports;
  system.build.wootingProfileShare = publisher;
  environment.systemPackages = [ shareWork ];
  assertions = [
    {
      assertion =
        profile.version == 15
        && profile.target.device == 10
        && profile.target.layout == 0
        && builtins.length profile.remap == 2;
      message = "The Mac Work transformation requires the reviewed schema 15 ANSI 80HE profile with two layers.";
    }
  ];
}
