# Pure evaluation fixture; no derivation is built or runtime assertion waived.
let
  helper = import ./sentry/crashpad-lock.nix;
  package = {
    overrideAttrs =
      f:
      f {
        nativeBuildInputs = [ "existing-tool" ];
        postPatch = "existing-post-patch\n";
        postBuild = "existing-post-build\n";
      };
  };
  default = helper { python3 = "/fixture-python"; } package;
  explicitFalse = helper {
    python3 = "/fixture-python";
    expectNoisyContention = false;
  } package;
  explicitTrue = helper {
    python3 = "/fixture-python";
    expectNoisyContention = true;
  } package;
  contains = needle: value: builtins.replaceStrings [ needle ] [ "" ] value != value;
in
assert default == explicitFalse;
assert !(contains "--expect-noisy-contention" default.postBuild);
assert contains "--expect-noisy-contention" explicitTrue.postBuild;
assert contains "crashpad_lock.py" default.postBuild;
assert contains "existing-post-build" default.postBuild;
assert
  default.nativeBuildInputs == [
    "existing-tool"
    "/fixture-python"
  ];
assert explicitTrue.postPatch == default.postPatch;
assert explicitTrue.nativeBuildInputs == default.nativeBuildInputs;
{
  defaultFalse = true;
  explicitFalse = true;
  explicitTrue = true;
  maintainedPythonPathAndExistingBuildAssertionsPreserved = true;
}
