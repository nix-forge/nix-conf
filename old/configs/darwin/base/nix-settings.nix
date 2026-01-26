{ config, lib, ... }:
# Using determinateNix for Darwin (macOS)
# Don't check config.nix.enable as it causes infinite recursion with determinateNix module
{
  determinateNix.customSettings = {
    # let the system decide the number of max jobs
    max-jobs = "auto";
    eval-cores = 0;
    cores = 0;

    allowed-users = [ "*" ];

    # only allow sudo users to manage the nix store
    trusted-users = [
      "root"
      "@admin"
    ];

    # build inside sandboxed environments
    sandbox = true;
    sandbox-fallback = false;

    # continue building derivations if one fails
    keep-going = true;

    # If we haven't received data for >= 20s, retry the download
    stalled-download-timeout = 20;

    # bail early on missing cache hits
    connect-timeout = 5;

    # show more log lines for failed builds
    log-lines = 30;

    # enable extra experimental features
    extra-experimental-features = [
      "nix-command"
      "flakes"
      "parallel-eval"
      "parse-toml-timestamps"
      "pipe-operators"
      "blake3-hashes"
      "verified-fetches"
      "fetch-tree"
      "git-hashing"
      "external-builders"
    ];

    # Note: external-builders is not allowed in determinateNix.customSettings
    # as it's managed by the determinateNix module

    # don't warn that my git tree is dirty it is known through git
    warn-dirty = false;

    # maximum number of parallel TCP connections used to fetch imports and binary caches, 0 means no limit
    http-connections = 35;

    # Whether to accept nix configuration from a flake without displaying a Y/N prompt.
    accept-flake-config = false;

    # for direnv GC roots
    keep-derivations = true;
    keep-outputs = true;

    # use binary cache, this is not gentoo
    # external builders can also pick up those substituters
    builders-use-substitutes = true;
  };

  environment.etc."nix/nix.custom.conf".text = lib.mkAfter ''
    !include ${config.age.secrets.nix-access-tokens.path}
  '';
}
