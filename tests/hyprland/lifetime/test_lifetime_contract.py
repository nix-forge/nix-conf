"""Keep actual crash identity, complete scenario coverage and clean exit mandatory."""

import pytest
from hyprland.lifetime.lifetime_contract import (
    require_baseline,
    require_child_first_control,
    require_repaired,
)


def test_raw_crash_requires_precise_source_failure() -> None:
    """Setup errors and unrelated crashes cannot establish the raw regression."""
    require_baseline(134, "CSubsurface::posRelativeToParent")
    for status, report in (
        (0, "posRelativeToParent"),
        (1, "EGL_BAD_PARAMETER"),
        (124, "probe timeout"),
        (134, "unrelated crash"),
    ):
        with pytest.raises(AssertionError):
            require_baseline(status, report)


def test_repaired_requires_all_twenty_cases_and_clean_manager_exit() -> None:
    """Missing, reordered or failed scenarios and abnormal exits fail closed."""
    expected = [
        (scenario, iteration, 0)
        for scenario in ("orphan", "disconnect", "feedback", "child-first")
        for iteration in range(5)
    ]
    clean = {"status": 0, "code": 1, "result": "success"}
    require_repaired(expected, clean)
    for results in (
        expected[:-1],
        [*expected, expected[0]],
        list(reversed(expected)),
        [("orphan", 0, 1), *expected[1:]],
    ):
        with pytest.raises(AssertionError):
            require_repaired(results, clean)
    with pytest.raises(AssertionError):
        require_repaired(expected, {"status": 137, "code": 2, "result": "signal"})


def test_parent_control_requires_client_and_clean_manager_exit() -> None:
    """Preflight success alone cannot replace the real raw child-first client."""
    clean = {"status": 0, "code": 1, "result": "success"}
    require_child_first_control([("child-first", 0, 0)], clean)
    for results in ([], [("orphan", 0, 0)], [("child-first", 0, 1)]):
        with pytest.raises(AssertionError):
            require_child_first_control(results, clean)
    with pytest.raises(AssertionError):
        require_child_first_control(
            [("child-first", 0, 0)], {"status": 0, "code": 1, "result": "timeout"}
        )
