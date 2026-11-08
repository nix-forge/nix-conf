"""Fail closed unless the original parent dereference or full lifecycle is proven."""

SCENARIOS = ("orphan", "disconnect", "feedback", "child-first")
ITERATIONS = 5


def require_baseline(status: int, reports: str) -> None:
    """Reject failures without the precise source-level parent dereference."""
    assert status != 0, "Untouched source unexpectedly survived parent-first teardown"
    assert "posRelativeToParent" in reports, "No precise parent-lifetime crash report"


def require_repaired(results: list[tuple[str, int, int]], shutdown: dict) -> None:
    """Preserve all twenty cases and actual successful compositor shutdown."""
    expected = [
        (scenario, iteration, 0)
        for scenario in SCENARIOS
        for iteration in range(ITERATIONS)
    ]
    assert results == expected, results
    assert shutdown == {"status": 0, "code": 1, "result": "success"}, shutdown


def require_child_first_control(
    results: list[tuple[str, int, int]], shutdown: dict
) -> None:
    """Require the untouched client control and clean manager exit."""
    assert results == [("child-first", 0, 0)], results
    assert shutdown == {"status": 0, "code": 1, "result": "success"}, shutdown
