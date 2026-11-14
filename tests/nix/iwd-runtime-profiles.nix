{
  inputs,
  pkgs,
  myLib,
}:
let
  inherit (import ./module-fixtures.nix { inherit inputs pkgs myLib; }) systemFor;
  configuration = systemFor [
    ../../modules/nixos/network/iwd-profiles.nix
    { networking.wireless.iwd.runtimeProfiles.fixture.source = "/run/credentials/wifi"; }
  ];
  tools = configuration.system.build.iwdProfileTools;
in
(import ../python-check.nix { inherit pkgs; }) {
  name = "iwd-runtime-profile-tests";
  files = [ ../runtime_profiles/test_iwd_native.py ];
  testPaths = [ "tests/runtime_profiles/test_iwd_native.py" ];
  selection = "nix_integration";
  nativeBuildInputs = [ pkgs.openssl ];
  environment = {
    IWD_MATERIALIZER = "${tools}/materialize";
    IWD_VALIDATOR = "${tools}/validate";
  };
}
