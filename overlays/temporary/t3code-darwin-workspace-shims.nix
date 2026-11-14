_: {
  reason = "pnpm's generated workspace shims misdetect default-path helpers under Darwin's system shell, so the official T3 Code build cannot find sed.";
  upstream = "https://github.com/NixOS/nixpkgs/blob/4a002bbb33286e165f7af5b4595879d184deed28/pkgs/by-name/t3/t3code/unwrapped.nix";
  removal = "The selected official recipe patches workspace executable shebangs before use, or pnpm's generated shims resolve helpers correctly under Darwin's system shell.";
  reviewedRevision = "4a002bbb33286e165f7af5b4595879d184deed28";
  inputPath = [ "nixpkgs-t3code" ];
  apply =
    package:
    package.overrideAttrs (old: {
      preBuild =
        (old.preBuild or "") + "\n" + builtins.readFile ./scripts/t3code-darwin-workspace-shims.sh;
    });
}
