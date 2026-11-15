{ pkgs, desktop }:
let
  inherit (pkgs) lib;
  cfg = desktop.config;
  unit = name: cfg.systemd.services.${name};
  app = unit "bookorbit";
  db = unit "bookorbit-native-db";
  site = cfg.homelab.operations.lanHttps.sites.bookorbit;
  host = "bookorbit.${cfg.homelab.operations.lanHttps.domain}";
  vpnPath = "/run/netns/${cfg.homelab.vpn.namespace.name}";
  intakeMount = lib.findFirst (
    mount: mount.where == "/run/bookorbitmedia/intake"
  ) null cfg.systemd.mounts;
  checks = [
    cfg.homelab.desktopBookDiscovery.enable
    cfg.homelab.desktopBookDiscovery.shared
    cfg.homelab.apps.bookorbit.enable
    cfg.homelab.apps.prowlarr.proxyOnly
    (lib.elem "prowlarr" cfg.homelab.networkPolicy.localOnlyServices)
    (!lib.elem "prowlarr" cfg.homelab.networkPolicy.directServices)
    ((unit "prowlarr").serviceConfig.IPAddressDeny == [ "any" ])
    (lib.elem "${cfg.homelab.vpn.namespace.bindAddress}/32" (unit "prowlarr")
    .serviceConfig.IPAddressAllow)
    # The native process retains the VPN and media boundaries of the service.
    (!(cfg.virtualisation.oci-containers.containers ? bookorbit))
    (!(cfg.virtualisation.oci-containers.containers ? bookorbit-db))
    (!(cfg.systemd.services ? podman-bookorbit))
    (!(cfg.systemd.services ? podman-bookorbit-db))
    (!(cfg.systemd.services ? bookorbit-images))
    (lib.elem "DATABASE_URL=postgresql:///bookorbit?host=/run/bookorbit-postgres&user=bookorbit" app.serviceConfig.Environment)
    (lib.elem "HOST=${cfg.homelab.vpn.namespace.bindAddress}" app.serviceConfig.Environment)
    (lib.elem "BOOK_DOCK_PATH=/intake/dock" app.serviceConfig.Environment)
    (lib.hasInfix " -k /run/bookorbit-postgres -c listen_addresses= " db.serviceConfig.ExecStart)
    (db.serviceConfig.RuntimeDirectoryMode == "0700")
    (db.serviceConfig.User == app.serviceConfig.User && db.serviceConfig.User == "bookorbit")
    (lib.elem "bookorbit-native-db.service" app.requires)
    (lib.elem "bookorbit-native-db.service" (unit "bookorbit-migrate").requires)
    (lib.elem "/run/bookorbitmedia/intake:/intake" app.serviceConfig.BindPaths)
    (lib.elem "/run/bookorbitmedia/library0:/books/audiobooks" app.serviceConfig.BindPaths)
    (lib.elem "/run/bookorbitmedia/library1:/books/books" app.serviceConfig.BindPaths)
    (lib.elem "run-bookorbitmedia-intake.mount" app.requires)
    (lib.elem "run-bookorbitmedia-library0.mount" app.requires)
    (lib.elem "run-bookorbitmedia-library1.mount" app.requires)
    (
      intakeMount != null
      && intakeMount.what == "${cfg.homelab.storage.downloadsDir}/torrents/bookorbit"
      && intakeMount.options == "bind,rw"
    )
    (
      cfg.homelab.apps.qbittorrent.configuration.categories.bookorbit.savePath
      == cfg.homelab.apps.bookorbit.acquisition.downloadDir
    )
    (lib.all (name: (unit name).serviceConfig.NetworkNamespacePath == vpnPath) [
      "bookorbit-metadata-policy"
      "bookorbit-bootstrap"
      "bookorbit-prowlarr-namespace-bridge"
      "bookorbit"
    ])
    (lib.elem "bookorbit-secrets.service" app.requires)
    (lib.elem "homelab-books-bootstrap.service" app.requires)
    (lib.elem "bookorbit-media-access.service" app.requires)
    (lib.elem "homelab-storage.service" (unit "bookorbit-media-access").requires)
    (lib.elem cfg.homelab.storage.rootDir (unit "bookorbit-media-access").serviceConfig.ReadWritePaths)
    (lib.elem "bookorbit.service" (unit "bookorbit-metadata-policy").requires)
    (lib.elem "bookorbit-metadata-policy.service" (unit "bookorbit-bootstrap").requires)
    (lib.elem "bookorbit-prowlarr-namespace-bridge.service" (unit "bookorbit-bootstrap").requires)
    (lib.elem "homelab-integrate-prowlarr.service" (unit "bookorbit-bootstrap").requires)
    (lib.elem "homelab-configure-qbittorrent.service" (unit "bookorbit-bootstrap").requires)
    (lib.elem "qbittorrent-username:${cfg.nixSeal.secrets.homelab-qbittorrent-username.path}" (unit "bookorbit-bootstrap")
    .serviceConfig.LoadCredential)
    (lib.elem "qbittorrent-password:${cfg.nixSeal.secrets.homelab-qbittorrent-password.path}" (unit "bookorbit-bootstrap")
    .serviceConfig.LoadCredential)
    (lib.elem "prowlarr-api-key:${cfg.nixSeal.secrets.homelab-prowlarr-api-key.path}" (unit "bookorbit-bootstrap")
    .serviceConfig.LoadCredential)
    ((unit "bookorbit-prowlarr-host-bridge").serviceConfig.IPAddressDeny == [ "any" ])
    ((unit "bookorbit-prowlarr-namespace-bridge").serviceConfig.IPAddressAllow == [ "127.0.0.0/8" ])
    # Native PostgreSQL uses the private Unix socket; app secrets never need a DB password.
    (lib.all (credential: !(lib.hasPrefix "postgres-password:" credential))
      (unit "bookorbit-secrets").serviceConfig.LoadCredential
    )
    (lib.elem "jwt-secret:${cfg.nixSeal.secrets.homelab-bookorbit-jwt-secret.path}" (unit "bookorbit-secrets")
    .serviceConfig.LoadCredential)
    ((unit "bookorbit-secrets").serviceConfig.RuntimeDirectoryMode == "0700")
    (lib.elem "admin-password:${cfg.nixSeal.secrets.homelab-bookorbit-admin-password.path}" (unit "bookorbit-bootstrap")
    .serviceConfig.LoadCredential)
    (lib.elem "bookorbit.service" (unit "bookorbit-bootstrap").bindsTo)
    (lib.elem "vpn-confinement-netns@${cfg.homelab.vpn.namespace.name}.service" app.requires)
    (lib.all
      (
        name:
        lib.elem "-/run/systemd/resolve/io.systemd.Resolve" (unit name).serviceConfig.InaccessiblePaths
      )
      [
        "bookorbit"
        "bookorbit-metadata-policy"
        "bookorbit-bootstrap"
      ]
    )
    (lib.elem "/var/lib/bookorbit" cfg.homelab.operations.state.bookorbit.paths)
    (lib.elem "/var/lib/bookorbit" cfg.hardware.storage.encryptedRoot.backup.paths)
    (lib.elem cfg.homelab.apps.bookorbit.acquisition.dockDir cfg.hardware.storage.encryptedRoot.backup.paths)
    (site.allowedCIDRs == null && cfg.homelab.operations.lanHttps.allowedCIDRs != [ ])
    (site.upstream == "http://${cfg.homelab.vpn.namespace.bindAddress}:13006")
    (lib.hasInfix "img-src 'self' data: blob:"
      cfg.services.nginx.virtualHosts.${host}.locations."/".extraConfig
    )
    (lib.hasInfix "connect-src 'self'"
      cfg.services.nginx.virtualHosts.${host}.locations."/".extraConfig
    )
    (lib.hasInfix "if (!-f /run/bookorbit-metadata/ready)"
      cfg.services.nginx.virtualHosts.${host}.locations."/".extraConfig
    )
    (lib.hasInfix "if (!-f /run/bookorbit-bootstrap/ready)"
      cfg.services.nginx.virtualHosts.${host}.locations."/".extraConfig
    )
    (!lib.elem 13006 cfg.networking.firewall.allowedTCPPorts)
  ];
  failed = lib.imap0 (index: item: if item then null else toString index) checks;
in
assert lib.assertMsg (lib.all (item: item) checks)
  "Book discovery policy checks failed: ${
    lib.concatStringsSep "," (lib.filter (item: item != null) failed)
  }";
pkgs.runCommand "book-discovery-policy" { } "touch $out"
