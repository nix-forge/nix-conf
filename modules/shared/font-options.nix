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
    optionalEmoji.enable = lib.mkEnableOption "explicit alternate emoji families without changing the default";
  };
}
