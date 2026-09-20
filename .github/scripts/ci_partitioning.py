"""Deterministically assign weighted CI work to independent runners."""

from __future__ import annotations

import json
import math
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from collections.abc import Mapping, Sequence
    from pathlib import Path

DEFAULT_WEIGHT = 1.0


def _weight(value: object, *, name: str) -> float:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        raise TypeError(f"Weight for {name} must be a number")
    result = float(value)
    if not math.isfinite(result) or result <= 0:
        raise ValueError(f"Weight for {name} must be finite and positive")
    return result


def load_weights(path: Path) -> tuple[float, dict[str, float]]:
    """Read relative work weights and tolerate retired check names.

    Returns:
        The default weight and the known check-specific weights.

    Raises:
        TypeError: A JSON value has an invalid type.

    """
    raw = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(raw, dict):
        raise TypeError("CI weight file must contain an object")

    default = _weight(raw.get("default", DEFAULT_WEIGHT), name="default")
    entries = raw.get("weights", {})
    if not isinstance(entries, dict):
        raise TypeError("CI weight file 'weights' must contain an object")

    weights: dict[str, float] = {}
    for name, value in entries.items():
        if not isinstance(name, str) or not name:
            raise TypeError("CI weight names must be nonempty strings")
        weights[name] = _weight(value, name=name)
    return default, weights


def partition_names(
    names: Sequence[str],
    partition_count: int,
    *,
    default_weight: float = DEFAULT_WEIGHT,
    weights: Mapping[str, float] | None = None,
) -> list[list[str]]:
    """Balance names with a deterministic greedy weighted assignment.

    Returns:
        A list of nonempty partitions in stable runner order.

    Raises:
        ValueError: The partition count, input names, or weights are invalid.

    """
    if partition_count < 1:
        raise ValueError("Partition count must be positive")
    if len(names) < partition_count:
        raise ValueError("Partition count cannot exceed the number of items")
    if len(set(names)) != len(names):
        raise ValueError("Partition items must be unique")
    default_weight = _weight(default_weight, name="default")
    known_weights = weights or {}

    def item_weight(name: str) -> float:
        return _weight(known_weights.get(name, default_weight), name=name)

    ordered = sorted(names, key=lambda name: (-item_weight(name), name))
    partitions = [[] for _ in range(partition_count)]
    loads = [0.0] * partition_count
    for name in ordered:
        index = min(
            range(partition_count),
            key=lambda candidate: (
                loads[candidate],
                len(partitions[candidate]),
                candidate,
            ),
        )
        partitions[index].append(name)
        loads[index] += item_weight(name)
    return partitions


def partition_load(
    names: Sequence[str],
    *,
    default_weight: float = DEFAULT_WEIGHT,
    weights: Mapping[str, float] | None = None,
) -> float:
    """Return the estimated cost of one assigned partition.

    Returns:
        The sum of the configured relative weights.

    """
    known_weights = weights or {}
    return sum(
        _weight(known_weights.get(name, default_weight), name=name) for name in names
    )
