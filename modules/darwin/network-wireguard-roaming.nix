{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.wireguardRoaming;
  interfaces = config.networking.wg-quick.interfaces;
  selectedInterface = interfaces.${cfg.interfaceName} or null;
  inherit (lib)
    getExe
    mkEnableOption
    mkIf
    mkOption
    types
    ;

  controller = cfg.package;

  controllerArguments = [
    "--private-key-file"
    (if selectedInterface == null then "" else selectedInterface.privateKeyFile)
    "--interface"
    cfg.interfaceName
    "--auto-connect"
    (if cfg.autoConnect then "true" else "false")
    "--ipv6-policy"
    cfg.ipv6Policy
    "--reconcile-interval"
    (toString cfg.reconcileIntervalSeconds)
    "--activation-timeout"
    (toString cfg.activationTimeoutSeconds)
    "--connectivity-check-url"
    (if cfg.connectivityCheckURL == null then "" else cfg.connectivityCheckURL)
  ];

  control = pkgs.writeShellScriptBin "wireguard-roaming" ''
    exec ${getExe controller} ${lib.escapeShellArgs controllerArguments} "$@"
  '';
in
{
  options.services.wireguardRoaming = {
    enable = mkEnableOption "a standalone WireGuard client controller for macOS";

    package = mkOption {
      type = types.package;
      default = pkgs.wireguard-roaming-controller;
      defaultText = lib.literalExpression "pkgs.wireguard-roaming-controller";
      description = "Package containing the standalone WireGuard controller.";
    };

    interfaceName = mkOption {
      type = types.strMatching "[a-zA-Z0-9_=+.-]{1,15}";
      default = "home-vpn";
      description = "Name of an existing non-autostart wg-quick interface.";
    };

    autoConnect = mkOption {
      type = types.bool;
      default = false;
      description = ''
        Keep the tunnel connected on every usable network. When false, launchd
        does not run a background controller and `wireguard-roaming up` and
        `wireguard-roaming down` provide manual control.
      '';
    };

    ipv6Policy = mkOption {
      type = types.enum [
        "allow-bypass"
        "block-while-connected"
      ];
      default = "allow-bypass";
      description = ''
        IPv6 handling when the profile has no IPv6 default route. The blocking
        policy adds temporary IPv6 blackhole routes only while the IPv4 tunnel
        is connected, then removes them before disconnecting.
      '';
    };

    reconcileIntervalSeconds = mkOption {
      type = types.ints.between 5 3600;
      default = 15;
      description = "Maximum delay before network and tunnel state are reconciled.";
    };

    activationTimeoutSeconds = mkOption {
      type = types.ints.between 3 60;
      default = 15;
      description = "Time allowed for a fresh handshake and connectivity check.";
    };

    connectivityCheckURL = mkOption {
      type = types.nullOr types.str;
      default = "https://www.apple.com/library/test/success.html";
      description = ''
        HTTPS URL checked before and after tunnel activation. Failure leaves or
        returns the Mac to its ordinary network. Set null only if handshake
        validation alone is sufficient.
      '';
    };

    logFile = mkOption {
      type = types.str;
      default = "/var/log/wireguard-roaming.log";
      description = "Controller log containing policy states but no network identifiers.";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = selectedInterface != null;
        message = "services.wireguardRoaming.interfaceName must select a networking.wg-quick interface.";
      }
      {
        assertion = selectedInterface == null || !selectedInterface.autostart;
        message = "The roaming wg-quick interface must set autostart = false.";
      }
      {
        assertion =
          selectedInterface == null
          || (
            selectedInterface.privateKeyFile != null
            && lib.hasPrefix "/" selectedInterface.privateKeyFile
            && !lib.hasPrefix "/nix/store/" selectedInterface.privateKeyFile
          );
        message = "The roaming wg-quick interface must use a privateKeyFile outside /nix/store.";
      }
      {
        assertion = lib.hasPrefix "/" cfg.logFile;
        message = "services.wireguardRoaming.logFile must be absolute.";
      }
      {
        assertion = cfg.connectivityCheckURL == null || lib.hasPrefix "https://" cfg.connectivityCheckURL;
        message = "services.wireguardRoaming.connectivityCheckURL must use HTTPS.";
      }
    ];

    environment.systemPackages = [
      control
      controller
    ];

    launchd.daemons.wireguard-roaming = mkIf cfg.autoConnect {
      serviceConfig = {
        Label = "org.nixos.wireguard-roaming";
        ProgramArguments = [
          (getExe control)
          "run"
        ];
        RunAtLoad = true;
        KeepAlive = true;
        UserName = "root";
        ProcessType = "Background";
        ThrottleInterval = 10;
        ExitTimeOut = cfg.activationTimeoutSeconds + 20;
        Umask = 63;
        AbandonProcessGroup = false;
        WorkingDirectory = "/";
        StandardOutPath = cfg.logFile;
        StandardErrorPath = cfg.logFile;
      };
    };
  };
}
