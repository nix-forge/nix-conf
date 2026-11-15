# shellcheck shell=bash
# Preserve the modifier cargoTestFlags; these focused suites run afterward.
for selection in \
  'hyprshell-hyprland data::regular::current_workspace_schema_tests 2' \
  'hyprshell-exec-lib workspace_identity::workspace_identity_tests 4' \
  'hyprshell-exec-lib switch::workspace_dispatch_tests 3' \
  'hyprshell-core-lib transfer::structs::workspace_wire_contract_tests 1'; do
  read -r package filter count <<<"$selection"
  log="workspace-$package.log"
  status=0
  CARGO_TERM_COLOR=never cargo test --offline --release \
    --target @rustTarget@ \
    --package "$package" "$filter" -- >"$log" 2>&1 || status=$?
  cat "$log"
  test "$status" -eq 0
  grep -Fx "running $count tests" "$log" ||
    { test "$count" = 1 && grep -Fx 'running 1 test' "$log"; }
  grep -F "test result: ok. $count passed; 0 failed; 0 ignored;" "$log"
done
