{ lib }:
lib.extend (
  _final: _prev: {
    my = {
      # Example: A helper to simplify shell scripts
      mkScript = name: text: (lib.pkgs.writeShellScriptBin name text);
    };
  }
)
