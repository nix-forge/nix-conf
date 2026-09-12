{ pkgs, config }:
assert pkgs.lib.all (assertion: assertion.assertion) config.assertions;
pkgs.runCommand "public-darwin-generated-config"
  {
    nativeBuildInputs = [
      pkgs.zsh
      pkgs.python3
    ];
    zshrc = pkgs.writeText "public-example-zshrc" config.environment.etc."zshrc".text;
    plist = config.environment.launchDaemons."org.nix-community.public-example-health.plist".source;
  }
  ''
    set -euo pipefail
    zsh -n "$zshrc"
    grep -F "alias gs='git status --short --branch'" "$zshrc"
    python3 - "$plist" <<'PY'
    import plistlib
    import subprocess
    import sys
    with open(sys.argv[1], 'rb') as source:
        job = plistlib.load(source)
    assert job['Label'] == 'org.nix-community.public-example-health'
    assert job['RunAtLoad'] is True
    assert len(job['ProgramArguments']) == 1
    subprocess.run(job['ProgramArguments'], check=True)
    PY
    touch "$out"
  ''
