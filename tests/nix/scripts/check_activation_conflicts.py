"""Check activation selection against managed, relocated and unrelated files."""

import json
import os
import subprocess  # ruff: ignore[suspicious-subprocess-import] - Execute the declared Bash fixture.
import tempfile
from pathlib import Path


def main() -> None:
    """Relocate fixture inputs and verify the generated activation arguments."""
    fixture_prefix = os.environ["FIXTURE_PREFIX"]
    policy = json.loads(Path(os.environ["manifest"]).read_text(encoding="utf-8"))
    activation = Path(os.environ["activation"]).read_text(encoding="utf-8")
    with tempfile.TemporaryDirectory() as directory:
        policy = {
            key: [value.replace(fixture_prefix, directory) for value in values]
            if isinstance(values, list)
            else values.replace(fixture_prefix, directory)
            for key, values in policy.items()
        }
        for name in policy["selected"] + policy["untouched"] + [policy["managed"]]:
            path = Path(name)
            path.parent.mkdir(parents=True, exist_ok=True)
            target = (
                policy["managedLink"]
                if name == policy["managed"]
                else policy["foreignLink"]
            )
            assert isinstance(target, str), target
            path.symlink_to(target)
        script = Path(directory) / "activation.sh"
        script.write_text(
            activation.replace(fixture_prefix, directory), encoding="utf-8"
        )
        for dry_run in [False, True]:
            result = subprocess.run(  # ruff: ignore[subprocess-without-shell-equals-true] - Declared executable and native fixture, no shell text.
                [os.environ["BASH_PROGRAM"], os.environ["fixtureBash"], str(script)],
                env=os.environ
                | {
                    "HOME": "/wrong-home",
                    "XDG_CONFIG_HOME": "/wrong-config",
                    "DRY_RUN": str(int(dry_run)),
                },
                capture_output=True,
                check=False,
            )
            assert result.returncode == 0, result.stderr
            assert not result.stderr, result.stderr
            requested = [
                os.fsdecode(value) for value in result.stdout.split(b"\0") if value
            ]
            assert sorted(requested) == (
                [] if dry_run else sorted(policy["selected"])
            ), requested
        for name in policy["untouched"]:
            assert Path(name).is_symlink(), name


if __name__ == "__main__":
    main()
