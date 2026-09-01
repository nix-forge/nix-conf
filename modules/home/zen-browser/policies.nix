{ config, ... }:
let
  inherit (config.programs.browserPolicy) firefox systemResolver;
in
{
  # Zen is Firefox-derived and consumes the same enterprise DNS policy.
  programs.zen-browser.policies = systemResolver.firefox // firefox.policies;
}
