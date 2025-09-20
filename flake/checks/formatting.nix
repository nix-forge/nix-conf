{ self, ... }:
{
  perSystem =
    { config, ... }:
    {
      checks.formatting = config.treefmt.build.check self;
    };
}
