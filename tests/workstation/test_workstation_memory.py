"""Capacity ranges, recovery waits and upward-only memory updates."""
# Pure policy seams and disposable cgroup files; no host limits are modified.
# ruff: file-ignore[magic-value-comparison]

import argparse
import importlib.util
import json
from pathlib import Path
from types import SimpleNamespace

import pytest

SOURCE = (
    Path(__file__).parents[2]
    / "modules/home/services/workstation-jobs-assets/workstation_memory.py"
)
SPEC = importlib.util.spec_from_file_location("workstation_memory", SOURCE)
assert SPEC is not None
assert SPEC.loader is not None
memory = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(memory)
MIB = 1024**2


def hierarchy(tmp_path: Path) -> tuple[Path, Path]:
    """Create an isolated hierarchy with independent parent and leaf usage.

    Returns:
        The fixture cgroup root and leaf.

    """
    root = tmp_path / "cgroup"
    parent = root / "work"
    leaf = parent / "job"
    leaf.mkdir(parents=True)
    for node, maximum, current in [(parent, 10, 4), (leaf, 8, 1)]:
        (node / "memory.max").write_text(str(maximum * MIB), encoding="utf-8")
        (node / "memory.current").write_text(str(current * MIB), encoding="utf-8")
        (node / "memory.high").write_text(
            str(maximum * MIB * 9 // 10), encoding="utf-8"
        )
        (node / "cgroup.events").write_text("populated 1\n", encoding="utf-8")
    return root, leaf


def test_all_ancestors_limit_available_capacity(tmp_path: Path) -> None:
    """A roomy leaf cannot spend RAM already used by its ancestor's siblings."""
    root, leaf = hierarchy(tmp_path)
    meminfo = tmp_path / "meminfo"
    meminfo.write_text("MemAvailable: 20480 kB\n", encoding="utf-8")
    sample = memory.snapshot(meminfo, leaf, root, tmp_path / "missing-psi")
    assert sample["ancestorRoomBytes"] == 6 * MIB
    assert sample["fullPressure"] is None
    assert memory.grant(sample, 3 * MIB, 8 * MIB, 2 * MIB, MIB, 50) == 6 * MIB
    (leaf.parent / "memory.max").unlink()
    unknown = memory.snapshot(meminfo, leaf, root, tmp_path / "missing-psi")
    assert memory.grant(unknown, MIB, 8 * MIB, 0, MIB, 50) == 0


@pytest.mark.parametrize(
    ("available", "ancestor", "pressure", "unused", "expected"),
    [
        (10, 9, 0, 0, 8),
        (5, 9, 0, 0, 3),
        (4, 9, 0, 0, 0),
        (20, 4, 0, 2, 0),
        (20, 9, 50, 0, 0),
        (10, 9, 0, 2, 6),
    ],
)
def test_range_keeps_minimum_reserve_pressure_and_unused_grants(
    available: int,
    ancestor: int,
    pressure: int,
    unused: int,
    expected: int,
) -> None:
    """Independent examples account for spare allowances before growth."""
    sample = {
        "availableBytes": available * MIB,
        "ancestorRoomBytes": ancestor * MIB,
        "fullPressure": pressure,
    }
    assert (
        memory.grant(sample, 3 * MIB, 8 * MIB, 2 * MIB, MIB, 50, unused * MIB)
        == expected * MIB
    )


def test_shortage_waits_then_persists_one_grant(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """An unavailable minimum causes no grant until the next recovery event."""
    samples = iter([{"availableBytes": MIB}, {"availableBytes": 7 * MIB}])
    waits = []
    monkeypatch.setattr(memory, "snapshot", lambda *_: next(samples))
    monkeypatch.setattr(
        memory,
        "Notifications",
        lambda *_: SimpleNamespace(wait=waits.append, close=lambda: None),
    )
    args = argparse.Namespace(
        receipt=tmp_path / "allocation.json",
        timeout=5,
        minimum=3,
        maximum=8,
        reserve=2,
        quantum=1,
        healthy_seconds=0,
        pressure_limit=50,
        pressure=tmp_path,
        group=None,
        root=tmp_path,
        meminfo=tmp_path,
    )
    assert memory.admit(args) == 0
    assert len(waits) == 1
    assert waits[0] > 0
    assert json.loads(args.receipt.read_text(encoding="utf-8"))["grantMiB"] == 5


@pytest.mark.parametrize("fail_high", [False, True])
def test_growth_only_increases_and_retains_partial_updates(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    fail_high: bool,
) -> None:
    """A failed high update never rolls back the larger hard cap."""
    root, leaf = hierarchy(tmp_path)
    (leaf / "memory.max").write_text(str(MIB), encoding="utf-8")
    (leaf / "memory.high").write_text(str(MIB * 9 // 10), encoding="utf-8")
    (leaf / "memory.current").write_text(str(MIB * 9 // 10), encoding="utf-8")
    path = tmp_path / "allocation.json"
    memory.save(path, {"grantMiB": 1, "maximumMiB": 2, "changes": []})
    writes = []

    def manager(command: list[str], **_kwargs: object) -> SimpleNamespace:
        if "show" in command:
            return SimpleNamespace(returncode=0, stdout="/work/job\n")
        key, value = command[-1].split("=")
        writes.append((key, int(value)))
        if key == "MemoryHigh" and fail_high:
            raise memory.subprocess.CalledProcessError(1, command)
        (leaf / ("memory.max" if key == "MemoryMax" else "memory.high")).write_text(
            value, encoding="utf-8"
        )
        return SimpleNamespace(returncode=0)

    async def discover(_args: argparse.Namespace) -> Path:  # ruff: ignore[unused-async] - manager discovery fixture
        return leaf

    monkeypatch.setattr(memory, "discover_group", discover)
    monkeypatch.setattr(memory.subprocess, "run", manager)
    monkeypatch.setattr(
        memory,
        "snapshot",
        lambda *_: {"availableBytes": 20 * MIB, "ancestorRoomBytes": 10 * MIB},
    )
    monkeypatch.setattr(
        memory,
        "Notifications",
        lambda *_: SimpleNamespace(wait=lambda _: None, close=lambda: None),
    )
    args = argparse.Namespace(
        receipt=path,
        systemctl="manager",
        unit="owned.service",
        root=root,
        pressure=tmp_path,
        meminfo=tmp_path,
        reserve=2,
        quantum=1,
        step=1,
        pressure_limit=50,
        pressure_hysteresis=5,
        growth_seconds=0,
        high_percent=90,
    )
    assert memory.grow(args) == int(fail_high)
    assert writes[0] == ("MemoryMax", 2 * MIB)
    assert int((leaf / "memory.max").read_text(encoding="utf-8")) == 2 * MIB
    record = json.loads(path.read_text(encoding="utf-8"))
    if fail_high:
        assert record["pendingGrantMiB"] == 2
        assert record["growthError"] == "CalledProcessError"
    else:
        assert record["grantMiB"] == 2
        assert len(record["changes"]) == 1


def test_expired_admission_never_returns_a_late_grant(
    tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    """Even recovered capacity is too late once the overall deadline expires."""
    clocks = iter([0, 2])
    monkeypatch.setattr(memory, "monotonic", lambda: next(clocks))
    monkeypatch.setattr(memory, "snapshot", lambda *_: {"availableBytes": 10 * MIB})
    monkeypatch.setattr(
        memory,
        "Notifications",
        lambda *_: SimpleNamespace(wait=lambda _: None, close=lambda: None),
    )
    args = argparse.Namespace(
        receipt=tmp_path / "allocation.json",
        timeout=1,
        minimum=3,
        maximum=8,
        reserve=2,
        quantum=1,
        healthy_seconds=0,
        pressure_limit=50,
        pressure=tmp_path,
        group=None,
        root=tmp_path,
        meminfo=tmp_path,
    )
    assert memory.admit(args) == 124
    record = json.loads(args.receipt.read_text(encoding="utf-8"))
    assert record["payloadLaunched"] is False
    assert record["phase"] == "admission-expired"
