# Azure CLI activation warning research

## Finding

The warning comes from the same activation command in
[`homes/desktop/local/azure-cli.nix`](../homes/desktop/local/azure-cli.nix) and
[`homes/macbook-pro-m4/local/azure-cli.nix`](../homes/macbook-pro-m4/local/azure-cli.nix):

```sh
az config set \
  core.collect_telemetry=no \
  core.disable_confirm_prompt=no \
  core.only_show_errors=no \
  core.output=jsonc \
  core.survey_message=no
```

Microsoft marks `az config` and `az config set` as experimental in the
[command reference](https://learn.microsoft.com/en-us/cli/azure/config?view=azure-cli-latest#az-config-set).
The Azure CLI 2.89.1 source used by this configuration registers the command
group with
[`is_experimental=True`](https://github.com/Azure/azure-cli/blob/azure-cli-2.89.1/src/azure-cli/azure/cli/command_modules/config/commands.py#L11-L15).
The warning is therefore expected. It does not mean that setting the values
failed.

The settings themselves are reasonable. Microsoft documents configuration for
output, confirmation prompts, telemetry, error-only output, and the survey
message on its
[Azure CLI configuration page](https://learn.microsoft.com/en-us/cli/azure/azure-cli-configuration?view=azure-cli-latest).
Keeping `disable_confirm_prompt=no` and `only_show_errors=no` preserves prompts
and warnings during normal interactive use.

## Supported choices

### Use environment variables

This is the best fit for this repository. Microsoft documents a corresponding
environment variable for every Azure CLI configuration value. The name is
`AZURE_{section}_{name}` in uppercase. Microsoft also defines the precedence as
command-line arguments first, environment variables second, and the config file
third. See
[CLI configuration values and environment variables](https://learn.microsoft.com/en-us/cli/azure/azure-cli-configuration?view=azure-cli-latest#cli-configuration-values-and-environment-variables).

The current settings map directly:

| Current setting | Environment variable |
| --- | --- |
| `core.collect_telemetry=no` | `AZURE_CORE_COLLECT_TELEMETRY=no` |
| `core.disable_confirm_prompt=no` | `AZURE_CORE_DISABLE_CONFIRM_PROMPT=no` |
| `core.only_show_errors=no` | `AZURE_CORE_ONLY_SHOW_ERRORS=no` |
| `core.output=jsonc` | `AZURE_CORE_OUTPUT=jsonc` |
| `core.survey_message=no` | `AZURE_CORE_SURVEY_MESSAGE=no` |

Declaring these through `home.sessionVariables` removes the activation-time
command and its warning. It also leaves `~/.azure/config` mutable for Azure CLI
state. The variables override a conflicting value in that file, which is the
expected behavior for preferences declared by Nix.

### Keep `az config set` and suppress this invocation

If persistent values in `~/.azure/config` are required, retaining the command is
defensible because Microsoft documents it for automation. Add
`--only-show-errors` to this invocation. Microsoft defines that global option as
"Only show errors, suppressing warnings" in the
[`az config set` reference](https://learn.microsoft.com/en-us/cli/azure/config?view=azure-cli-latest#az-config-set),
and documents that error-only mode suppresses experimental-command warnings in
the
[configuration key reference](https://learn.microsoft.com/en-us/cli/azure/azure-cli-configuration?view=azure-cli-latest#cli-configuration-values-and-environment-variables).

This quiets the warning but still makes Home Manager activation depend on an
experimental command. It is a fallback, not the preferred fix.

### Do not replace it with `az configure`

`az configure` is GA, but it is interactive and cannot set every current
preference. Microsoft explicitly directs automation and access to all options to
`az config`. See the
[`az configure` reference](https://learn.microsoft.com/en-us/cli/azure/reference-index?view=azure-cli-latest#az-configure).

Microsoft also documents the INI format at `$AZURE_CONFIG_DIR/config`, which is
`~/.azure/config` by default on Linux and macOS. Home Manager could generate or
edit that file, but owning the entire file would interfere with mutable CLI
state such as the selected cloud. A merge script would duplicate behavior that
the CLI already provides. Neither approach is better than environment variables
for these five preferences.

## Recommendation

Replace both `home.activation.azureCliPreferences` blocks with the five
`home.sessionVariables` entries above. Keep them in the host-local modules
because they are personal preferences. Do not manage the rest of `~/.azure`, and
do not silence warnings for ordinary Azure CLI commands.
