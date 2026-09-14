# Configure the shell prompt

The [Starship module](https://github.com/nix-forge/nix-conf/blob/main/modules/home/shells/starship.nix)
keeps the shell prompt in the same declarative configuration as other tools.
Use the source input from the [Git recipe](git.md):

```nix
{
  imports = [ (inputs.nix-conf-source + "/modules/home/shells/starship.nix") ];
}
```

Build your Home Manager configuration and inspect its generated
`.config/starship.toml`. After activation, start a fresh supported shell to see
its prompt integration.

The full module's glyphs depend on the terminal font. If symbols appear as empty
boxes, check the selected font or use the starter's deliberately small prompt
before adding decorative symbols. A prompt configuration does not install a
terminal font by itself.

For changes, use the Home Manager `programs.starship.settings` option and
[Starship's configuration reference](https://starship.rs/config/). Keep the prompt
short enough to leave room for commands at your normal terminal width.

The public consumer check builds the module with neutral account settings and
checks the generated configuration. The starter's VM separately demonstrates a
small prompt in a running shell.
