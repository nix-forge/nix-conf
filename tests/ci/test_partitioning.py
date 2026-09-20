"""Test deterministic weighted CI partitioning."""

from __future__ import annotations

import runpy
import sys
from pathlib import Path
from typing import TYPE_CHECKING, cast

if TYPE_CHECKING:
    from collections.abc import Callable, Mapping

import pytest

ROOT = Path(__file__).resolve().parents[2]
RUNNER = ROOT / ".github/scripts/run-flake-checks.py"
sys.path.insert(0, str(RUNNER.parent))
try:
    NAMESPACE = runpy.run_path(str(RUNNER), run_name="ci_partitioning_test")
finally:
    sys.path.pop(0)
partition_names = cast(
    "Callable[..., list[list[str]]]",
    NAMESPACE["partition_names"],
)
load_weights = cast(
    "Callable[[Path], tuple[float, dict[str, float]]]",
    NAMESPACE["load_weights"],
)

TWO_PARTITIONS = 2
DEFAULT_WEIGHT = 1


def test_weighted_items_are_distributed_without_duplication() -> None:
    """Give each runner a heavyweight check before filling cheap work."""
    names = [
        "heavy-a",
        "heavy-b",
        "heavy-c",
        "cheap-a",
        "cheap-b",
        "cheap-c",
    ]
    weights: Mapping[str, float] = {
        "heavy-a": 10,
        "heavy-b": 9,
        "heavy-c": 8,
    }

    partitions = partition_names(names, 3, weights=weights)

    assert sorted(name for partition in partitions for name in partition) == sorted(
        names
    )
    assert all(
        any(name.startswith("heavy-") for name in partition) for partition in partitions
    )


def test_checked_in_weight_file_is_valid() -> None:
    """Load the repository weights used by every native check shard."""
    default, weights = load_weights(ROOT / ".github/ci-check-weights.json")

    assert default == DEFAULT_WEIGHT
    assert "clamav-runtime" in weights


def test_unknown_items_use_the_default_weight() -> None:
    """Use the configured default for names absent from the weight file."""
    partitions = partition_names(
        ["a", "b", "c", "d"],
        TWO_PARTITIONS,
        default_weight=2,
        weights={"a": 4},
    )

    assert sorted(name for partition in partitions for name in partition) == [
        "a",
        "b",
        "c",
        "d",
    ]
    assert len(partitions[0]) == len(partitions[1]) == TWO_PARTITIONS


def test_invalid_partition_sizes_are_rejected() -> None:
    """Reject a matrix larger than the work it is meant to distribute."""
    with pytest.raises(ValueError, match="cannot exceed"):
        partition_names(["only"], TWO_PARTITIONS)
