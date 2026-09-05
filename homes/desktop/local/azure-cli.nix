_: {
  # Azure CLI supports AZURE_<section>_<name> for every configuration value.
  # Keep authentication and Azure DevOps organization/project defaults mutable
  # under ~/.azure while declaring these non-secret personal preferences here.
  home.sessionVariables = {
    AZURE_CORE_COLLECT_TELEMETRY = "no";
    AZURE_CORE_DISABLE_CONFIRM_PROMPT = "no";
    AZURE_CORE_ONLY_SHOW_ERRORS = "no";
    AZURE_CORE_OUTPUT = "jsonc";
    AZURE_CORE_SURVEY_MESSAGE = "no";
  };
}
