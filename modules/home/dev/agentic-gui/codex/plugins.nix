{
  config,
  lib,
  pkgs,
  ...
}:
let
  security = "codex-security@openai-curated-remote";
  disabledPlugins = [
    "presentations@openai-primary-runtime"
    "template-creator@openai-primary-runtime"
    "data-analytics@openai-curated-remote"
    "pages@openai-curated-remote"
    "sites@openai-curated-remote"
    "openai-templates@openai-curated-remote"
    "work-pets@openai-curated-remote"
  ];
in
{
  imports = [ ./settings.nix ];

  programs.chatgpt.settings = {
    plugins =
      lib.genAttrs disabledPlugins (_: {
        enabled = false;
      })
      // {
        "${security}".enabled = false;
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        "unified-computer-use@openai-bundled".enabled = false;
        "codex-app-tools@openai-bundled".enabled = false;
      };
    apps =
      lib.genAttrs
        [
          "asdk_app_6a83901dde988191b3f3cefdcc19acfa"
          "asdk_app_69a089a326dc8191b32a3f2553f5be2c"
          "connector_openai_pages"
          "connector_20205bf7d4e99a89d7154bb849718324"
          "connector_1p_4a72ddeef4c481918f92d8e8df18fb2c"
          "connector_1p_689987207de08191979cf68eca2941c6"
        ]
        (_: {
          enabled = false;
        });
    features = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux { computer_use = false; };
  };

  # No security skills or MCP are loaded in ordinary sessions. Select this
  # session-only layer explicitly with `codex --profile security`.
  programs.codex.profiles.security = lib.mkIf config.programs.codex.enable {
    plugins."${security}".enabled = true;
  };
}
