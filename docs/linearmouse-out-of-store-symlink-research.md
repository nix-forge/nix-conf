# LinearMouse out-of-store symlink research

## Conclusion

`config.lib.file.mkOutOfStoreSymlink` will stop LinearMouse 0.11.4 from
watching `/nix/store` only when the symlink's final destination is a regular
file outside the store. It is safe to use here, but wrapping the existing
`jsonFormat.generate` result directly will not help because that result is
still a store path.

The module keeps `programs.linearmouse.settings`, generates the JSON as it did
before, copies that JSON during activation to the dedicated user-owned path
`~/.local/state/home-manager/linearmouse/linearmouse.json`, and points
`xdg.configFile."linearmouse/linearmouse.json".source` at that path with
`mkOutOfStoreSymlink`. Create and populate the staging directory before
`setupLaunchAgents` so LinearMouse resolves the narrow directory when it
starts.

## Why it works

The current configuration resolves as:

```text
~/.config/linearmouse/linearmouse.json
  -> /nix/store/...-home-manager-files/.config/linearmouse/linearmouse.json
  -> /nix/store/...-linearmouse.json
```

Home Manager's function creates a store output that is itself a symlink to the
supplied path. Home Manager then links that output through `home-manager-files`
and into the home directory. Its pinned test checks this exact two-stage
behavior. [Pinned implementation](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/files.nix#L124-L138),
[pinned test](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/tests/modules/files/out-of-store-symlink.nix#L1-L26)

With the proposed staging file, the chain becomes:

```text
~/.config/linearmouse/linearmouse.json
  -> /nix/store/...-home-manager-files/.config/linearmouse/linearmouse.json
  -> /nix/store/...-linearmouse.json
  -> ~/.local/state/home-manager/linearmouse/linearmouse.json
```

LinearMouse does not stop at the first store link. Its canonicalizer walks
every path component and recursively follows absolute and relative symlinks
until it reaches the final path. [LinearMouse 0.11.4 symlink resolution](https://github.com/linearmouse/linearmouse/blob/df23b547ea0821c729eae1e6055bf3a018ab6b4f/LinearMouse/Utilities/FileWatcher.swift#L244-L299)

For each configuration path, the watcher adds a root for the logical path and,
when the file resolves elsewhere, another root for the resolved file's
directory. It then passes those roots to FSEvents. The current final path adds
`/nix/store`; the staged final path adds the dedicated staging directory
instead. The logical XDG path still causes LinearMouse to watch `~/.config`,
which is intentional so replacing or recreating the `linearmouse` directory is
noticed. [Root selection](https://github.com/linearmouse/linearmouse/blob/df23b547ea0821c729eae1e6055bf3a018ab6b4f/LinearMouse/Utilities/FileWatcher.swift#L154-L192),
[FSEvents setup](https://github.com/linearmouse/linearmouse/blob/df23b547ea0821c729eae1e6055bf3a018ab6b4f/LinearMouse/Utilities/FileWatcher.swift#L41-L93)

## Recommended module shape

Use a plain absolute string for `stagedConfigFile`. Do not derive it from the
generated store path.

```nix
let
  generatedConfig = jsonFormat.generate "linearmouse.json" cfg.settings;
  stagedConfigDirectory = "${config.xdg.stateHome}/home-manager/linearmouse";
  stagedConfigFile = "${stagedConfigDirectory}/linearmouse.json";
in
{
  xdg.configFile."linearmouse/linearmouse.json".source =
    config.lib.file.mkOutOfStoreSymlink stagedConfigFile;

  home.activation.installLinearMouseConfig =
    lib.hm.dag.entryBetween [ "setupLaunchAgents" ] [ "linkGeneration" ] ''
      run mkdir -p ${lib.escapeShellArg stagedConfigDirectory}
      run /usr/bin/install -m 0600 \
        ${lib.escapeShellArg generatedConfig} \
        ${lib.escapeShellArg "${stagedConfigFile}.tmp"}
      run /bin/mv -f \
        ${lib.escapeShellArg "${stagedConfigFile}.tmp"} \
        ${lib.escapeShellArg stagedConfigFile}
    '';
}
```

Home Manager maps `xdg.configFile` into `home.file`, builds the generation's
home-file links, and installs those links in `linkGeneration`. The activation
entry above therefore runs after the logical link is in place and before the
launch agent can start the app. [XDG mapping](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/misc/xdg/default.nix#L202-L210),
[home-file construction](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/files.nix#L423-L473),
[activation linking](https://github.com/nix-community/home-manager/blob/99c9ec63390f1d8c14d95d9e8b17cc29cfbd4e11/modules/files.nix#L187-L274)

## Limitations and checks

- The out-of-store file is writable. LinearMouse deliberately resolves the
  symlink before saving, so a GUI setting change can modify the staging file.
  The next Home Manager activation restores the declared JSON. [LinearMouse
  save path](https://github.com/linearmouse/linearmouse/blob/df23b547ea0821c729eae1e6055bf3a018ab6b4f/LinearMouse/Model/Configuration/Configuration.swift#L93-L110)
- LinearMouse watches both supported configuration locations and gives the
  legacy Application Support file precedence. Remove
  `~/Library/Application Support/linearmouse/linearmouse.json` if it exists.
  [Configuration path order](https://github.com/linearmouse/linearmouse/blob/df23b547ea0821c729eae1e6055bf3a018ab6b4f/LinearMouse/State/ConfigurationState.swift#L16-L42)
- After activation, `realpath ~/.config/linearmouse/linearmouse.json` must
  print the staging path and not a path under `/nix/store`. Restart LinearMouse,
  run a Nix build, and confirm its idle CPU use stays low.

## Repository verification

The implemented module keeps the existing inline settings and stages the
generated JSON at
`~/.local/state/home-manager/linearmouse/linearmouse.json`. A full host
evaluation built the `mkOutOfStoreSymlink` source and `readlink` returned that
external staging path. An isolated Home Manager build also confirmed the
`home-manager-files` link points to the helper's store link, whose target is
the external staging file. The generated activation command copies the current
JSON with mode `0600` and replaces it only when the content changes.
