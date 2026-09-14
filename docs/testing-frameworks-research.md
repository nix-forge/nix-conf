# Testing frameworks for workstation configuration

Reviewed: 2026-09-10. Scope: root repository at
`7fd38c80a2aabdb16674fba7231496fa4a575bee`, with Nixpkgs pinned to
`c5c4a43b0e8056328ec4529f735cabdb8f1942bb`. The development partition separately
pins Nixpkgs to `c043004d1c6985732bcc1cbc5a9c9aecbbb4e0f0`.
Upstream documentation was retrieved
on the review date. Recommendations below are engineering judgments informed
by those sources and the inspected checkout.

## Answer

Use pytest as the root Python test runner, Nix flake checks to supply dependencies
and execute isolated checks, and the NixOS test driver for operating-system
integration. Use `lib.runTests` for pure Nix contracts. These choices fit the
existing implementation and avoid introducing another environment manager.

Preserve useful unittest cases under pytest while improving their assertions and
fixtures. Converting every assertion to a new spelling would add little evidence.
The three submodules retain their own frameworks and validation commands, as
required by the [repository boundaries](../CONTRIBUTING.md#repository-boundaries).

## Findings and sources

Local observations at the reviewed revision:

- [Root checks](../flake/dev/checks.nix) invoke unittest discovery, standalone
  Python scripts, shell programs, and language-specific tools. Pytest is already
  a dependency of Python quality checks.
- [Backup recovery tests](../tests/storage/test_backup.py) already use pytest
  fixtures and parametrization. They exercise failure receipts and real Restic
  backup/restore behavior with disposable data.
- [Framework tests](../nix-config-framework/tests/default.nix) already use
  `lib.runTests` to check discovery, ordering, and invalid selectors.
- [ClamAV integration](../tests/nix/clamav-runtime.nix) exercises real systemd
  units with controlled executable fixtures. Its claim concerns unit lifecycle
  and namespaces, not antivirus detection quality.

| Framework | Source-backed capability | Recommendation for this repository |
| --- | --- | --- |
| pytest | Collects unittest classes, captures output, and supports focused selection. Regular pytest functions can request fixtures and parametrization; unittest methods cannot directly request those features. [Compatibility documentation](https://docs.pytest.org/en/stable/how-to/unittest.html) | Adopt as the common Python runner. Write new cases as functions; migrate existing classes when the change improves isolation or reduces repetition. |
| pytest-timeout | Interrupts tests exceeding a configured deadline and reports thread stacks. Termination and cleanup depend on the selected method. [Official documentation](https://github.com/pytest-dev/pytest-timeout) | Adopt as a last-resort bound for stalled tests. Keep explicit subprocess deadlines for controlled cleanup; use generous suite limits, not performance thresholds. |
| Nixpkgs `lib.runTests` | Compares named `expr` and `expected` values and returns failure records. Default discovery requires names beginning with `test`. [Pinned implementation](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/lib/debug.nix) | Use for pure helpers and evaluated configuration contracts. Assert the failure list is empty so evaluation cannot silently succeed. |
| Nixpkgs testers | Provides output comparison and NixOS test construction. `testEqualContents` compares files through Diffoscope. [Pinned implementation](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/build-support/testers/default.nix) | Use existing helpers where they express the requirement. Prefer parsing semantic fields when harmless formatting changes should pass. |
| NixOS VM tests | Builds disposable guests and drives commands through Python, including waiting for services and checking command success or failure. [Official tutorial](https://nix.dev/tutorials/nixos/integration-testing-using-virtual-machines.html) | Retain for boot, storage, permissions, and service integration. Require a suitable builder and bounded readiness checks. |
| nix-unit | Uses a structure compatible with `lib.debug.runTests` and reports individual evaluation failures through Nix's evaluator API. [Official documentation](https://nix-community.github.io/nix-unit/) | Reconsider if larger pure Nix suites need failure isolation. The current root does not need another runner to gain named assertions. |
| Hypothesis | Generates cases from strategies and integrates with pytest. [Official quickstart](https://hypothesis.readthedocs.io/en/latest/quickstart.html) | Defer until a concrete invariant needs broad input coverage, such as renderer escaping or preservation of unrelated configuration. Keep explicit regression examples alongside generated cases. |
| Bats-core | Provides Bash test cases, setup/teardown, and a `run` helper exposing status and output. [Official documentation](https://bats-core.readthedocs.io/en/stable/writing-tests.html) | Defer. Existing Python subprocess fixtures and isolated Nix shell checks already cover the present command interfaces. Reconsider for a substantial shell-specific suite. |

Pytest recommends `importlib` import mode for new projects and supports strict
configuration and marker checks. Those settings suit the root's separate test
directories and help catch configuration mistakes. Keep explicit discovery
boundaries so a root run cannot collect submodule tests or workstation probes.
The root Nixpkgs revision supplies pytest 9.0.3; implementation validation used
pytest 9.1.1 with Python 3.14.7 from the separate development partition. Keep
tool versions tied to their owning lockfile. [Pytest integration guidance](https://docs.pytest.org/en/stable/explanation/goodpractices.html),
[pinned package](https://github.com/NixOS/nixpkgs/blob/c5c4a43b0e8056328ec4529f735cabdb8f1942bb/pkgs/development/python-modules/pytest/default.nix).

Use per-test temporary paths for mutable data and parameterize examples of the
same requirement. Share fixtures only where setup is actually shared. These
facilities replace manual cleanup and repeated setup without hiding the behavior
under test. [Temporary paths](https://docs.pytest.org/en/stable/how-to/tmp_path.html),
[parametrization](https://docs.pytest.org/en/stable/how-to/parametrize.html).

## Implication for this repository

Organize tests by owning feature. Keep automated Python cases discoverable and
keep interactive probes explicitly invoked. Let focused Nix checks own native
dependencies, generated artifacts, and platform eligibility. A common runner
does not require every test language to become Python.

Retain tests that can detect a named behavior regression, including negative
cases. Replace source-text searches with public commands or evaluated output
where possible. Remove tautologies, duplicate policy inventories, and timing
thresholds unrelated to a requirement. A source-format assertion is justified
only when that exact format is part of the contract. These are review criteria,
not findings that every existing case has those defects.

## Validation and limits

This research inspected local source and primary documentation on Linux. It did
not execute framework benchmarks, native macOS tests, VM tests, or workstation
probes. Adoption does not establish those results. Runtime and build evidence
belongs to the implementation's validation record; evaluation alone does not
prove either. Full desktop system builds must follow the placement rule in
[AGENTS.md](../AGENTS.md).
