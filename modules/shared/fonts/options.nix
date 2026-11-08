{ lib, ... }: {
  options.typography = {
    designLibrary = lib.mkOption {
      type = lib.types.enum [
        "full"
        "curated"
        "none"
      ];
      default = "curated";
      description = "Optional design collection, independent of primary font roles and language coverage.";
    };
    restrictedFonts.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Include Apple fonts, Apple emoji and Windows evaluation fonts after reviewing permission for the intended use. This setting grants no rights.";
    };
    optionalEmoji.enable = lib.mkEnableOption "explicit alternate emoji families without changing the default";
  };
}
