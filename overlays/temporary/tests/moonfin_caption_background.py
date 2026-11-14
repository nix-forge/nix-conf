"""Run Moonfin's actual style writer against an observable fake mpv channel.

Usage: python3 moonfin_caption_background.py BACKEND_SOURCE DART_EXECUTABLE FIXTURE_SOURCE ANALYSIS_OPTIONS
The selected upstream source must pass. No Flutter packages or network are required.
"""

import pathlib
import subprocess  # ruff: ignore[suspicious-subprocess-import] - execute the pinned Dart interpreter
import sys
import tempfile


def method(source: str, signature: str) -> str:
    """Extract a balanced method body from the reviewed upstream source.

    Returns:
        The complete Dart method including its signature.

    """
    start = source.index(signature)
    opening = source.index("{", start)
    depth = 1
    end = opening + 1
    while depth:
        depth += (source[end] == "{") - (source[end] == "}")
        end += 1
    return source[start:end]


source = pathlib.Path(sys.argv[1]).read_text(encoding="utf-8")
methods = "\n".join(
    method(source, signature)
    for signature in (
        "Future<void> _writeSubtitleStyle(NativePlayer native)",
        "Future<void> _applyAssOverrideMode()",
        "static String _argbToMpvColor(int argb)",
        "static Map<String, String> subtitleBackgroundMpvProperties(int color)",
        "Future<void> _writeSubtitleFontSize(NativePlayer native)",
    )
)
program = (
    pathlib
    .Path(sys.argv[3])
    .read_text(encoding="utf-8")
    .replace("// @methods@", methods)
)
with tempfile.TemporaryDirectory(prefix="moonfin-caption-test-") as directory:
    test = pathlib.Path(directory) / "test.dart"
    test.write_text(program, encoding="utf-8")
    options = pathlib.Path(directory) / "analysis_options.yaml"
    options.write_text(
        pathlib.Path(sys.argv[4]).read_text(encoding="utf-8"), encoding="utf-8"
    )
    subprocess.run([sys.argv[2], "analyze", "--fatal-infos", directory], check=True)  # ruff: ignore[subprocess-without-shell-equals-true] - analyze only the assembled fixture with the pinned interpreter
    subprocess.run([sys.argv[2], str(test)], check=True)  # ruff: ignore[subprocess-without-shell-equals-true] - argv supplied by the Nix build, never a shell
