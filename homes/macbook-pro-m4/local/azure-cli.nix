{ lib, pkgs, ... }:
let
  azureCli = pkgs.azure-cli.withExtensions [ pkgs.azure-cli.extensions.azure-devops ];
in
{
  # Authentication, Azure DevOps organization, and project defaults remain
  # mutable user state. These non-secret local preferences are safe to restore.
  home.activation.azureCliPreferences = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    umask 077
    ${azureCli}/bin/az config set \
      core.collect_telemetry=no \
      core.disable_confirm_prompt=no \
      core.only_show_errors=no \
      core.output=jsonc \
      core.survey_message=no
  '';
}
