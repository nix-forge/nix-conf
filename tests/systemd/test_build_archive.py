"""Root every external source without requiring paths for relative inputs."""

import json
import runpy
from pathlib import Path

import pytest

LINUX_BUILD = runpy.run_path(
    str(Path(__file__).parents[2] / "scripts/build_linux_package.py")
)
ARCHIVE_PATHS = LINUX_BUILD["archive_paths"]


@pytest.mark.parametrize(
    ("configured", "available", "expected"),
    [(8, 16, 8), (4, 16, 4), (8, 2, 2), (0, 16, 8), (0, 1, 1)],
)
def test_compiler_budget_preserves_host_policy_and_cpu_headroom(
    monkeypatch: pytest.MonkeyPatch, configured: int, available: int, expected: int
) -> None:
    """Honor the host budget and limit workers to available CPU resources."""
    monkeypatch.setattr(
        LINUX_BUILD["os"],
        "sched_getaffinity",
        lambda _: set(range(available)),
        raising=False,
    )
    monkeypatch.setattr(
        LINUX_BUILD["subprocess"], "check_output", lambda *_, **__: str(configured)
    )
    assert LINUX_BUILD["compiler_budget"]() == expected


def test_relative_input_keeps_external_dependencies_rooted() -> None:
    """A nested relative input shares its source but retains external inputs."""
    archive = {
        "path": "/nix/store/parent-source",
        "inputs": {
            "local": {
                "inputs": {
                    "nested": {
                        "inputs": {
                            "external": {"path": "/nix/store/external-source"},
                        },
                    },
                },
            },
            "duplicate": {"path": "/nix/store/external-source"},
        },
    }
    assert ARCHIVE_PATHS(archive) == {
        "/nix/store/parent-source",
        "/nix/store/external-source",
    }


def test_relative_input_cannot_hide_non_store_dependency() -> None:
    """Every separately rooted source still needs to be in the Nix store."""
    with pytest.raises(ValueError, match="non-store source"):
        ARCHIVE_PATHS({"inputs": {"invalid": {"path": "/not-store/source"}}})


@pytest.mark.parametrize(
    ("exit_code", "expected_status"), [(None, 0), ("cancelled", 1), (130, 130)]
)
def test_exit_receipt_preserves_python_exit_semantics(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    exit_code: str | int | None,
    expected_status: int,
) -> None:
    """Finalize an interrupted job without replacing its original exception."""
    monkeypatch.setattr(
        LINUX_BUILD["sys"],
        "argv",
        [
            "build",
            "fixture",
            "aarch64-linux",
            "aarch64-linux",
            "fixture",
            str(tmp_path),
            "fixture.nix",
        ],
    )
    monkeypatch.setattr(
        LINUX_BUILD["os"], "sched_getaffinity", lambda _: {0}, raising=False
    )
    monkeypatch.setattr(LINUX_BUILD["subprocess"], "check_output", lambda *_, **__: "1")
    monkeypatch.setattr(LINUX_BUILD["signal"], "signal", lambda *_, **__: None)

    def interrupted(*_args: object, **_kwargs: object) -> None:
        raise SystemExit(exit_code)

    monkeypatch.setattr(LINUX_BUILD["subprocess"], "run", interrupted)
    with pytest.raises(SystemExit) as error:
        LINUX_BUILD["main"]()
    assert error.value.code == exit_code
    receipt = json.loads((tmp_path / "status.json").read_text(encoding="utf-8"))
    assert receipt["exit_status"] == expected_status
