_: {
  reason = "pnpm's generated workspace shims misdetect default-path helpers under Darwin's system shell, so the official T3 Code build cannot find sed.";
  upstream = "https://github.com/NixOS/nixpkgs/blob/4a002bbb33286e165f7af5b4595879d184deed28/pkgs/by-name/t3/t3code/unwrapped.nix";
  removal = "The selected official recipe patches workspace executable shebangs before use, or pnpm's generated shims resolve helpers correctly under Darwin's system shell.";
  reviewedRevision = "04906337b6d53e8bb0eaf0470ae9f070a4d4eb55";
  inputPath = [ "nixpkgs" ];
  apply =
    package:
    package.overrideAttrs (old: {
      preBuild =
        (old.preBuild or "")
        + "\n"
        + (''
          # shellcheck shell=bash
          # pnpm's hook patches root node_modules. Cover generated workspace bins after
          # the unchanged upstream preparation, which can regenerate executable shims.
          while IFS= read -r -d "" directory; do
            patchShebangs "$directory"
          done < <(find apps packages -type d -path '*/node_modules/.bin' -print0)
        '');
    });
}
