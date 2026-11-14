{
  lib,
  fix,
  guard,
}:
let
  original = rec {
    type = "derivation";
    pname = "t3code";
    version = "0.1.6";
    outPath = "/nix/store/11111111111111111111111111111111-official-outer";
    meta = {
      mainProgram = "t3code-desktop";
    };
    passthru = {
      unwrapped = {
        outPath = "/nix/store/22222222222222222222222222222222-official-unwrapped";
      };
      resourceMonitor = {
        outPath = "/nix/store/33333333333333333333333333333333-resource-monitor";
      };
      tests.preserved = true;
      updateScript = [ "unchanged" ];
    };
    inherit (passthru) unwrapped resourceMonitor;
    override =
      args:
      assert
        builtins.attrNames args == [
          "t3code-resource-monitor"
          "t3code-unwrapped"
        ];
      assert args.t3code-resource-monitor == resourceMonitor;
      assert args.t3code-unwrapped.version == version;
      assert args.t3code-unwrapped.meta == meta;
      {
        outPath = "/nix/store/44444444444444444444444444444444-official-provider-wrapped-gui";
      };
  };
  layer = fix.apply original;
  succeeds = value: (builtins.tryEval (builtins.deepSeq value true)).success;
  lifecycle = fix // {
    name = "t3code-darwin-vendor-gui";
  };
  existing = {
    outPath = "/nix/store/55555555555555555555555555555555-existing-server";
  };
  chained = original // {
    serverPackage = existing;
    passthru = original.passthru // {
      serverPackage = existing;
    };
  };
in
{
  modelOnlyNotNativeAcceptance = true;
  incomingCliTreeOnly = layer.paths == [ original ];
  noIncomingBuilderReplay = !(layer ? buildCommand);
  nameVersionMetaPreserved =
    layer.pname == original.pname && layer.version == original.version && layer.meta == original.meta;
  fullIncomingPassthruPreserved =
    removeAttrs layer.passthru [
      "serverPackage"
      "vendorGui"
    ] == original.passthru;
  stableServerIsOriginalCli = layer.passthru.serverPackage == original;
  preexistingServerAliasPreserved = (fix.apply chained).passthru.serverPackage == existing;
  unwrappedUnchanged = layer.passthru.unwrapped == original.unwrapped;
  monitorUnchanged = layer.passthru.resourceMonitor == original.resourceMonitor;
  signedBundleHasNoFixup = layer.passthru.vendorGui.dontFixup;
  signedBundleHasNoStrip = layer.passthru.vendorGui.dontStrip;
  signedBundleHasNoCompiler = layer.passthru.vendorGui.dontBuild;
  ordinaryInstallCheckRequired = layer.passthru.vendorGui.doInstallCheck;
  archivePinExact =
    layer.passthru.vendorGui.src.hash == "sha256-GkXOqvyqqMWmL63LFr1CxJVQfFkcme0iOTQkCm6B9pk=";
  noSignedMetadataRewrite =
    !(lib.hasInfix "codesign" layer.postBuild) && !(lib.hasInfix "Info.plist" layer.postBuild);
  guiReusesOfficialProviderFactory = lib.hasInfix "/nix/store/44444444444444444444444444444444-official-provider-wrapped-gui/bin/t3code-desktop" layer.postBuild;
  exactCliTargetRequired = lib.hasInfix "-ef ${lib.escapeShellArg "${original}/bin/t3"}" layer.postBuild;
  changedVersionRejected = !(succeeds (fix.apply (original // { version = "0.1.7"; })));
  missingUnwrappedRejected = !(succeeds (fix.apply (removeAttrs original [ "unwrapped" ])));
  missingMonitorRejected = !(succeeds (fix.apply (removeAttrs original [ "resourceMonitor" ])));
  reviewedRevisionAccepted = succeeds (
    guard lifecycle "4a002bbb33286e165f7af5b4595879d184deed28" original
  );
  changedRevisionRejected = !(succeeds (guard lifecycle "unreviewed" original));
}
