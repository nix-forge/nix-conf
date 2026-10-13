"""Keep capability baseline results specific and never accept disabled tests."""

import importlib.util
import unittest
from pathlib import Path

_SPEC = importlib.util.spec_from_file_location(
    "darwin_package_result", Path(__file__).with_name("darwin-package-result.py")
)
if _SPEC is None or _SPEC.loader is None:
    message = "Cannot load local native proof classifier"
    raise ImportError(message)
_RESULT = importlib.util.module_from_spec(_SPEC)
_SPEC.loader.exec_module(_RESULT)


def _sentry(**updates: object) -> dict[str, object]:
    return {
        "name": "main - nix-functional-tests:sentry",
        "result": "FAIL",
        "returncode": 1,
        "stdout": "No crash dump found in fixture after crash",
        "stderr": "bootstrap_check_in fixture: Permission denied (1100)",
        **updates,
    }


class DarwinResultTest(unittest.TestCase):
    """Verify honest permission baselines and real native test execution."""

    @staticmethod
    def test_specific_native_sentry_denial() -> None:
        """Test specific native sentry denial."""
        _RESULT.sentry([_sentry()], 1)

    def test_sentry_skip_rejected(self) -> None:
        """Test sentry skip rejected."""
        with self.assertRaisesRegex(ValueError, "never SKIP"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native-proof regressions do not require pytest.
            _RESULT.sentry([_sentry(result="SKIP", returncode=77)], 1)

    def test_sentry_missing_denial_rejected(self) -> None:
        """Test sentry missing denial rejected."""
        with self.assertRaisesRegex(ValueError, "explicit Mach"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native-proof regressions do not require pytest.
            _RESULT.sentry([_sentry(stderr="a generic error")], 1)

    def test_unknown_service_is_not_permission_denial(self) -> None:
        """Test unknown service is not permission denial."""
        with self.assertRaisesRegex(ValueError, "explicit Mach"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native-proof regressions do not require pytest.
            _RESULT.sentry(
                [
                    _sentry(
                        stderr="bootstrap_look_up fixture: Unknown service name (1102)"
                    )
                ],
                1,
            )

    def test_sentry_requires_actual_missing_dump(self) -> None:
        """Test sentry requires actual missing dump."""
        with self.assertRaisesRegex(ValueError, "no-crashdump"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native-proof regressions do not require pytest.
            _RESULT.sentry([_sentry(stdout="unrelated failure")], 1)

    def test_other_case_rejected(self) -> None:
        """Test other case rejected."""
        with self.assertRaisesRegex(ValueError, "exact Sentry"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native-proof regressions do not require pytest.
            _RESULT.sentry([_sentry(name="main - nix-functional-tests:unrelated")], 1)

    def test_more_than_one_native_case_rejected(self) -> None:
        """Test more than one native case rejected."""
        with self.assertRaisesRegex(ValueError, "only one"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native-proof regressions do not require pytest.
            _RESULT.sentry([_sentry(), _sentry()], 1)

    def test_sentry_success_rejected(self) -> None:
        """Test sentry success rejected."""
        with self.assertRaisesRegex(ValueError, "failing"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native-proof regressions do not require pytest.
            _RESULT.sentry([_sentry()], 0)

    @staticmethod
    def test_actual_home_case_passes() -> None:
        """Test actual home case passes."""
        _RESULT.home(
            "test command::tests::test_elevated_darwin_home_is_absolute ... ok\n1 passed; 0 failed;"
        )

    def test_zero_matching_home_tests_rejected(self) -> None:
        """Test zero matching home tests rejected."""
        with self.assertRaisesRegex(ValueError, "did not pass"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native-proof regressions do not require pytest.
            _RESULT.home("running 0 tests\n0 passed; 0 failed;")

    @staticmethod
    def test_precise_deploy_watcher_denial() -> None:
        """Test precise deploy watcher denial."""
        _RESULT.deploy(
            "test tests::confirmation_watcher_observes_immediate_canary_removal ... FAILED\ncreate confirmation watcher: FSEventStream: Operation not permitted",
            101,
        )

    def test_generic_deploy_failure_rejected(self) -> None:
        """Test generic deploy failure rejected."""
        with self.assertRaisesRegex(ValueError, "FSEvents"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native-proof regressions do not require pytest.
            _RESULT.deploy(
                "test tests::confirmation_watcher_observes_immediate_canary_removal ... FAILED\ncreate confirmation watcher: an unrelated error",
                101,
            )

    def test_deploy_build_failure_rejected(self) -> None:
        """Test deploy build failure rejected."""
        with self.assertRaisesRegex(ValueError, "did not fail exactly"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native-proof regressions do not require pytest.
            _RESULT.deploy("error: dependency compilation failed", 101)

    @staticmethod
    def test_preserved_sentinel_cases_pass() -> None:
        """Require both unchanged non-watcher scenarios to pass."""
        _RESULT.sentinel(
            "test tests::wait_cancelled_when_cancel_file_already_exists ... ok\n1 passed; 0 failed;",
            "sentinel-existing",
        )
        _RESULT.sentinel(
            "test tests::remove_activation_cancel_clears_the_sentinel ... ok\n1 passed; 0 failed;",
            "sentinel-removal",
        )

    def test_zero_matching_sentinel_case_rejected(self) -> None:
        """Reject a successful Cargo command that selected no real test."""
        with self.assertRaisesRegex(ValueError, "did not pass"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library regression fixtures.
            _RESULT.sentinel("running 0 tests\n0 passed; 0 failed;", "sentinel-removal")


def _registered(
    name: str, suite: str = "nix-functional-tests:main"
) -> dict[str, object]:
    return {
        "name": name,
        "suite": [suite],
        "cmd": ["/nix/store/fixture-bash/bin/bash", "-x", f"{name}.sh"],
        "timeout": 300,
        "protocol": "exitcode",
        "is_parallel": True,
        "priority": 0,
    }


class FunctionalRegistrationTest(unittest.TestCase):
    """Check real Meson registration sets preserve every other native case."""

    @staticmethod
    def test_only_sentry_removed() -> None:
        """Preserve both main and other suites after the exact Sentry exclusion."""
        preserved = [
            _registered("init"),
            _registered("build", "nix-functional-tests:ca"),
        ]
        _RESULT.registration([*preserved, _registered("sentry")], preserved)

    def test_additional_test_removed_is_rejected(self) -> None:
        """An unrelated omitted test cannot qualify as the narrow policy."""
        with self.assertRaisesRegex(ValueError, "beyond"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native registration regressions.
            _RESULT.registration(
                [_registered("init"), _registered("build"), _registered("sentry")],
                [_registered("init")],
            )

    def test_retained_sentry_is_rejected(self) -> None:
        """A no-op source patch does not exclude the required native case."""
        cases = [_registered("init"), _registered("sentry")]
        with self.assertRaisesRegex(ValueError, "beyond"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native registration regressions.
            _RESULT.registration(cases, cases)

    def test_missing_raw_sentry_is_rejected(self) -> None:
        """Require the actual raw suite to expose the original case."""
        with self.assertRaisesRegex(ValueError, "exactly one"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native registration regressions.
            _RESULT.registration([_registered("init")], [_registered("init")])

    def test_wrong_sentry_suite_is_rejected(self) -> None:
        """An identically named case in a different suite is not the reviewed target."""
        with self.assertRaisesRegex(ValueError, "exactly one"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native registration regressions.
            _RESULT.registration(
                [_registered("init"), _registered("sentry", "nix-functional-tests:ca")],
                [_registered("init")],
            )

    def test_added_case_is_rejected(self) -> None:
        """Do not accept unexpected native test registration changes."""
        with self.assertRaisesRegex(ValueError, "beyond"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native registration regressions.
            _RESULT.registration(
                [_registered("init"), _registered("sentry")],
                [_registered("init"), _registered("unexpected")],
            )

    def test_duplicate_case_is_rejected(self) -> None:
        """Duplicate native names must not disappear through set normalization."""
        with self.assertRaisesRegex(ValueError, "Duplicate"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native registration regressions.
            _RESULT.registration(
                [_registered("init"), _registered("sentry")],
                [_registered("init"), _registered("init")],
            )

    def test_changed_timeout_is_rejected(self) -> None:
        """Preserve surviving test invocation, timeout and execution flags."""
        changed = _registered("init") | {"timeout": 0}
        with self.assertRaisesRegex(ValueError, "execution contract"):  # ruff: ignore[pytest-unittest-raises-assertion] - Standard library native registration regressions.
            _RESULT.registration(
                [_registered("init"), _registered("sentry")], [changed]
            )


if __name__ == "__main__":
    unittest.main()
