{ lib, ... }: {
  reason = "The native builder store mount rejects GNU cp permission preservation in the Zen wrapper.";
  upstream = "https://github.com/NixOS/nixpkgs/blob/0968519e14f7aa7d3e9b389682bd74d2b51c8ce8/pkgs/applications/networking/browsers/firefox/wrapper.nix";
  removal = "The upstream wrapper copies successfully on the native builder without this substitution.";
  reviewedRevision = "c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    let
      incompatibleCopy = "cp -P --no-preserve=mode,ownership --remove-destination";
      compatibleCopy = "cp -P --remove-destination";
    in
    # The Determinate native builder's store mount rejects the permission
    # update made by this GNU cp option combination. The Zen wrapper already
    # runs chmod immediately after the copy, so dropping these options keeps
    # the intended mode while making the wrapper portable across builders.
    browser: wrapperArgs:
    let
      wrapped = package browser wrapperArgs;
    in
    if lib.hasPrefix "zen-" (browser.pname or "") then
      wrapped.overrideAttrs (old: {
        buildCommand =
          assert lib.assertMsg (lib.hasInfix incompatibleCopy old.buildCommand)
            "Zen wrapper copy workaround no longer matches the upstream build command";
          builtins.replaceStrings [ incompatibleCopy ] [ compatibleCopy ] old.buildCommand;
      })
    else
      wrapped;
}
