{
  config,
  lib,
  pkgs,
  ...
}:
let
  gamesMountPoint = "/mnt/games";
  steamLibraryConfigure = pkgs.writeShellApplication {
    name = "steam-library-configure";
    runtimeInputs = [
      pkgs.procps
      pkgs.util-linux
    ];
    text = ''
      if ! mountpoint --quiet ${lib.escapeShellArg gamesMountPoint}; then
        echo "Steam library: ${gamesMountPoint} is not mounted; leaving Steam unchanged." >&2
        exit 0
      fi

      # Steam rewrites this file while it is running.  Defer rather than risk
      # losing a client-side change; the command remains available for a safe
      # manual retry after Steam exits.
      if pgrep --uid "$USER" --full '[s]team' >/dev/null; then
        echo "Steam library: Steam is running; retry after it exits." >&2
        exit 0
      fi

      ${lib.getExe pkgs.python3} - ${lib.escapeShellArg config.xdg.dataHome} ${lib.escapeShellArg gamesMountPoint} <<'PY'
      import os
      import re
      import sys
      import tempfile
      from pathlib import Path

      data_home = Path(sys.argv[1])
      library_path = sys.argv[2]
      candidates = [
          data_home / "Steam" / "steamapps" / "libraryfolders.vdf",
          Path.home() / ".steam" / "steam" / "steamapps" / "libraryfolders.vdf",
      ]
      config_path = next((path for path in candidates if path.exists()), candidates[0])
      config_path.parent.mkdir(parents=True, exist_ok=True)

      if config_path.exists():
          contents = config_path.read_text(encoding="utf-8")
          mode = config_path.stat().st_mode & 0o777
      else:
          contents = '"libraryfolders"\n{\n}\n'
          mode = 0o600

      token_pattern = re.compile(r'"(?:\\.|[^"\\])*"|[{}]')
      tokens = list(token_pattern.finditer(contents))
      if len(tokens) < 2 or tokens[0].group() != '"libraryfolders"':
          print(f"Steam library: {config_path} is not a libraryfolders VDF; leaving it unchanged.", file=sys.stderr)
          raise SystemExit(0)

      root_start = next((index for index, token in enumerate(tokens[1:], 1) if token.group() == "{"), None)
      if root_start is None:
          print(f"Steam library: {config_path} has no libraryfolders object; leaving it unchanged.", file=sys.stderr)
          raise SystemExit(0)

      depth = 1
      root_end = None
      library_ids = set()
      for index in range(root_start + 1, len(tokens)):
          token = tokens[index].group()
          if token == "{":
              depth += 1
          elif token == "}":
              depth -= 1
              if depth == 0:
                  root_end = tokens[index]
                  break
          elif depth == 1 and index + 1 < len(tokens) and tokens[index + 1].group() == "{":
              library_ids.add(token[1:-1])

      if root_end is None:
          print(f"Steam library: {config_path} has unbalanced braces; leaving it unchanged.", file=sys.stderr)
          raise SystemExit(0)

      path_pattern = re.compile(r'^\s*"path"\s*"((?:\\.|[^"\\])*)"\s*$', re.MULTILINE)
      configured_paths = {
          match.group(1).replace(r"\\", "\\").replace(r'\\"', '"')
          for match in path_pattern.finditer(contents)
      }
      if library_path in configured_paths:
          print(f"Steam library: {library_path} is already configured.")
          raise SystemExit(0)

      library_id = next(str(index) for index in range(1000000) if str(index) not in library_ids)
      entry = (
          f'\t"{library_id}"\n'
          '\t{\n'
          f'\t\t"path" "{library_path}"\n'
          '\t\t"label" "Games"\n'
          '\t\t"contentid" "0"\n'
          '\t\t"totalsize" "0"\n'
          '\t\t"apps"\n'
          '\t\t{\n'
          '\t\t}\n'
          '\t}\n'
      )
      insertion = root_end.start()
      prefix = "" if contents[:insertion].endswith("\n") else "\n"
      updated = contents[:insertion] + prefix + entry + contents[insertion:]

      with tempfile.NamedTemporaryFile("w", encoding="utf-8", dir=config_path.parent, delete=False) as temporary:
          temporary.write(updated)
          temporary_name = temporary.name
      os.chmod(temporary_name, mode)
      os.replace(temporary_name, config_path)
      print(f"Steam library: added {library_path} to {config_path}.")
      PY
    '';
  };
in
lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
  home.packages = [ steamLibraryConfigure ];

  # This updates the Steam-owned VDF only when it is safe to do so.  It is an
  # additive, idempotent migration: existing library entries are retained.
  home.activation.configureSteamLibrary = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
    ${lib.getExe steamLibraryConfigure}
  '';
}
