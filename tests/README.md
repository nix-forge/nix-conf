# Tests

Start with [the testing guide](../docs/testing.md) for commands, execution layers,
fixture conventions, and review decisions. Framework comparisons and sources are
in [the research note](../docs/research/testing-frameworks-research.md).

`just test-python` runs automated root Python behavior tests. `just test-ci`
runs tests requiring a Nix daemon. Generated secret and Git-hook fixtures run
through their named flake checks. Files named `check_*` are explicit probes;
read their arguments and prerequisites before running them.

Automated host integration suites live under `tests/homelab/`, including the
vault importer inventory and credential-preservation fixtures. Their source
programs live with the host homelab modules. Browser fixtures use purpose-based
filenames, so inserting lines in a probe does not change a fixture name.
