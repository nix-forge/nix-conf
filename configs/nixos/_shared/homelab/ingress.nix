{
  profile ? "home-server",
}:
{ config, lib, ... }:
let
  stack = import ./stack-values.nix { inherit profile; };

  mkHost = service: "${service}.${stack.baseDomain}";

  ingressAuthEnabled = stack.ingressAuth.enabled;

  authUserPlaceholder = "{$" + stack.ingressAuth.usernameEnv + "}";
  authPasswordPlaceholder = "{$" + stack.ingressAuth.passwordHashEnv + "}";

  authDirective =
    if ingressAuthEnabled then
      ''
        basic_auth {
          ${authUserPlaceholder} ${authPasswordPlaceholder}
        }
      ''
    else
      "";

  caddyReverseProxy = upstream: ''
    reverse_proxy ${upstream}
  '';

  mkDefaultVhost =
    upstream:
    {
      requireAuth ? false,
    }:
    {
      useACMEHost = stack.wildcardHost;
      extraConfig = ''
        ${lib.optionalString (ingressAuthEnabled && requireAuth) authDirective}
        ${caddyReverseProxy upstream}
      '';
    };

  mkQbittorrentVhost =
    upstream:
    {
      requireAuth ? false,
    }:
    {
      useACMEHost = stack.wildcardHost;
      extraConfig = ''
        ${lib.optionalString (ingressAuthEnabled && requireAuth) authDirective}
        reverse_proxy ${upstream} {
          header_up Host {upstream_hostport}
        }
      '';
    };

  mkServiceVhost =
    serviceName:
    let
      service = stack.services.${serviceName};
      builder =
        if service ? reverseProxyNeedsHostHeader && service.reverseProxyNeedsHostHeader then
          mkQbittorrentVhost
        else
          mkDefaultVhost;
    in
    builder service.upstream {
      requireAuth = service.requireIngressAuth or false;
    };

  mkHomepageServiceEntry =
    serviceName:
    let
      service = stack.services.${serviceName};
    in
    {
      "${service.displayName}" = {
        inherit (service) icon;
        href = service.homepageHref;
        inherit (service) description;
        inherit (service) weight;
      };
    };

  expectedServiceNames = lib.sort lib.lessThan (lib.attrNames stack.services);
  configuredServiceNames = lib.sort lib.lessThan (
    lib.concatLists (lib.attrValues stack.serviceOrder)
  );

  homepageServices = lib.mapAttrs (
    _: serviceNames: map mkHomepageServiceEntry serviceNames
  ) stack.serviceOrder;

  serviceVirtualHosts = lib.mapAttrs' (
    serviceName: _: lib.nameValuePair (mkHost serviceName) (mkServiceVhost serviceName)
  ) stack.services;

  serviceRedirectConfig = lib.concatMapStringsSep "\n\n" (serviceName: ''
    handle_path /${serviceName}* {
      redir https://${mkHost serviceName}:{http.request.port}{uri} 302
    }
  '') configuredServiceNames;
in
{
  assertions = [
    {
      assertion = lib.hasAttrByPath [ "age" "secrets" "cloudflare-acme-env" ] config;
      message = "age.secrets.cloudflare-acme-env must exist for host-homelab-ingress.";
    }
    {
      assertion =
        (!ingressAuthEnabled)
        || lib.hasAttrByPath [ "age" "secrets" stack.ingressAuth.envSecretName ] config;
      message = "age.secrets.${stack.ingressAuth.envSecretName} must exist when homelab ingress auth is enabled.";
    }
    {
      assertion = configuredServiceNames == expectedServiceNames;
      message = "serviceOrder must include each service in stack.services exactly once.";
    }
  ];

  age.secrets.${stack.ingressAuth.envSecretName} = lib.mkIf ingressAuthEnabled {
    owner = config.services.caddy.user;
    group = config.services.caddy.group;
    mode = "0400";
  };

  networking.firewall.allowedTCPPorts = [
    22
    443
  ];

  security.acme.defaults.email = stack.acmeEmail;

  security.acme.certs.${stack.wildcardHost} = {
    domain = "*.${stack.baseDomain}";
    extraDomainNames = [ stack.baseDomain ];
    dnsProvider = "cloudflare";
    credentialFiles.CF_DNS_API_TOKEN_FILE = config.age.secrets.cloudflare-acme-env.path;
    inherit (config.services.caddy) group;
    enableDebugLogs = lib.mkDefault stack.isVm;
  };

  services.homepage-dashboard.settings = {
    title = lib.mkDefault (if stack.isVm then "Home Server VM" else "Home Server");
    description = lib.mkDefault (
      if stack.isVm then
        "VM profile for homelab ingress and service validation."
      else
        "Local control room for media and apps."
    );
    color = lib.mkDefault (if stack.isVm then "zinc" else "amber");
    layout = {
      Media = {
        style = "row";
        columns = 2;
        icon = "jellyfin.png";
      };
      Automation = {
        style = "row";
        columns = 3;
        icon = "prowlarr.png";
      };
      Downloads = {
        style = "row";
        columns = 2;
        icon = "qbittorrent.png";
      };
      Apps = {
        style = "row";
        columns = 2;
        icon = "vaultwarden.png";
      };
    };
  };

  services.homepage-dashboard.allowedHosts = lib.mkIf stack.isVm (lib.mkForce "*");
  services.homepage-dashboard.services = homepageServices;

  services.caddy.virtualHosts = {
    ${stack.baseDomain} = {
      useACMEHost = stack.wildcardHost;
      extraConfig = ''
        respond /healthz 200 {
          body "ok"
        }
        ${lib.optionalString stack.isVm serviceRedirectConfig}
        ${caddyReverseProxy "127.0.0.1:8082"}
      '';
    };
    ${mkHost "home"} = mkDefaultVhost "127.0.0.1:8082" { requireAuth = false; };
  }
  // serviceVirtualHosts;

  services.caddy.environmentFile =
    lib.mkIf ingressAuthEnabled
      config.age.secrets.${stack.ingressAuth.envSecretName}.path;
}
