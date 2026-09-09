{ pkgs, myLib }:
let
  localControlLibrary =
    (pkgs.lib.evalModules {
      modules = [
        ../../homes/macbook-pro-m4/local/local-control/config-helpers.nix
        {
          options.lib = pkgs.lib.mkOption {
            type = pkgs.lib.types.attrsOf pkgs.lib.types.anything;
            default = { };
          };
        }
      ];
    }).config.lib.localControl;
  cssChecker = myLib.desktop.mkGtkCssChecker { inherit pkgs; };
  writePowerShell = myLib.writers.writePowerShell { inherit pkgs; };
  caddyChecker = localControlLibrary.mkLocalControlConfigChecker { inherit pkgs; };
  localControl = localControlLibrary.mkLocalControlConfigs {
    inherit pkgs;
    cfg = {
      bindAddress = "127.0.0.1";
      dashboardDirectory = "/srv/control dashboard";
      privateHostname = "control.example.invalid";
      webPort = 5173;
      apiPort = 8788;
      proxyPort = 8443;
    };
  };
in
{
  gtk-css-parser = pkgs.runCommand "gtk-css-parser" { } ''
    printf '%s\n' '* { color: #123456; }' > valid.css
    ${cssChecker}/bin/check-gtk-css valid.css
    printf '%s\n' '* { color: this-is-not-a-color; }' > invalid.css
    if ${cssChecker}/bin/check-gtk-css invalid.css; then
      echo "GTK CSS parser accepted invalid CSS" >&2
      exit 1
    fi
    if ${cssChecker}/bin/check-gtk-css missing.css; then
      echo "GTK CSS parser accepted a missing file" >&2
      exit 1
    fi
    printf '%s\n' '@import url("missing.css");' > missing-import.css
    if ${cssChecker}/bin/check-gtk-css missing-import.css; then
      echo "GTK CSS parser accepted a missing import" >&2
      exit 1
    fi
    touch "$out"
  '';
  powershell-parser = writePowerShell "valid.ps1" ''
    # Successful validation must not execute this script.
    throw 'This program must only be parsed'
  '';
  powershell-checker-lint = myLib.writers.writePowerShell {
    inherit pkgs;
    compatibilityVersions = [ "7.0" ];
  } "check-powershell.ps1" (builtins.readFile ../../lib/writers/check-powershell.ps1);
  powershell-invalid-syntax = pkgs.testers.testBuildFailure' {
    drv = writePowerShell "invalid.ps1" "function Broken {";
    expectedBuilderLogEntries = [ "Missing closing '}'" ];
  };
  powershell-unused-variable = pkgs.testers.testBuildFailure' {
    drv = writePowerShell "unused.ps1" "$unused = 1";
    expectedBuilderLogEntries = [ "PSUseDeclaredVarsMoreThanAssignments" ];
  };
  powershell-empty-catch = pkgs.testers.testBuildFailure' {
    drv = writePowerShell "empty-catch.ps1" "try { throw 'fixture' } catch { }";
    expectedBuilderLogEntries = [ "PSAvoidUsingEmptyCatchBlock" ];
  };
  powershell-guest-compatibility = pkgs.testers.testBuildFailure' {
    drv = writePowerShell "incompatible.ps1" "$null = $true ? 'yes' : 'no'";
    expectedBuilderLogEntries = [ "PSUseCompatibleSyntax" ];
  };
  caddyfile-config = pkgs.runCommand "local-control-caddy-contract" { } ''
    ${pkgs.lib.getExe caddyChecker} ${localControl.proxyConfig} > config.json
    ${pkgs.lib.getExe pkgs.jq} -e '
      ([.apps.http.servers[].listen[]] | sort) == ["127.0.0.1:5173", "127.0.0.1:8443"]
      and ([.. | objects | select(.handler? == "reverse_proxy") | .upstreams[].dial] == ["127.0.0.1:8788", "127.0.0.1:8788"])
      and ([.. | objects | .client_authentication? // empty | .mode] == ["require_and_verify"])
    ' config.json
    cp config.json "$out"
  '';
  caddy-provisioning-failure = pkgs.testers.testBuildFailure' {
    drv = pkgs.runCommand "invalid-caddy-certificate" { } ''
      ${pkgs.lib.getExe caddyChecker} ${pkgs.writeText "missing-certificate.Caddyfile" ''
        https://localhost:8443 {
          tls /missing-server.pem /missing-server.key
          respond "fixture"
        }
      ''} > "$out"
    '';
    expectedBuilderLogEntries = [ "missing-server.pem" ];
  };
  openssl-extension-configs =
    pkgs.runCommand "openssl-extension-configs" { nativeBuildInputs = [ pkgs.openssl ]; }
      ''
        openssl req -new -newkey rsa:2048 -noenc -subj /CN=configuration-test \
          -keyout test.key -out test.csr 2>/dev/null
        openssl x509 -req -in test.csr -signkey test.key -days 1 \
          -extfile ${localControl.clientCertificateExtensions} -out client.crt
        openssl x509 -in client.crt -noout -ext extendedKeyUsage | grep -F 'TLS Web Client Authentication'
        openssl x509 -req -in test.csr -signkey test.key -days 1 \
          -extfile ${localControl.serverCertificateExtensions} -out server.crt
        openssl x509 -in server.crt -noout -ext extendedKeyUsage | grep -F 'TLS Web Server Authentication'
        openssl x509 -in server.crt -noout -ext subjectAltName | grep -F 'DNS:control.example.invalid, IP Address:127.0.0.1'
        touch "$out"
      '';
}
