{ config, ... }:
let
  inherit (config.programs.browserPolicy) firefox systemResolver;
in
{
  programs.firefox.policies = systemResolver.firefox // firefox.policies;
}
