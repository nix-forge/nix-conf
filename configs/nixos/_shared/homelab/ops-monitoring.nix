{
  profile ? "home-server",
}:
{ config, ... }:
let
  stack = import ./stack-values.nix { inherit profile; };
in
{
  services.prometheus = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9090;
    globalConfig.scrape_interval = "30s";
    exporters.node = {
      enable = true;
      enabledCollectors = [
        "systemd"
        "processes"
      ];
    };
    scrapeConfigs = [
      {
        job_name = "prometheus";
        static_configs = [ { targets = [ "127.0.0.1:9090" ]; } ];
      }
      {
        job_name = "node";
        static_configs = [
          { targets = [ "127.0.0.1:${toString config.services.prometheus.exporters.node.port}" ]; }
        ];
      }
      {
        job_name = "ingress";
        metrics_path = "/healthz";
        static_configs = [ { targets = [ "127.0.0.1:443" ]; } ];
        scheme = "https";
        tls_config = {
          insecure_skip_verify = true;
        };
      }
    ];
    rules = [
      ''
        groups:
          - name: homelab-core
            rules:
              - alert: PrometheusTargetDown
                expr: up{job=~"prometheus|node"} == 0
                for: 5m
                labels:
                  severity: warning
                annotations:
                  summary: "Prometheus target down"
                  description: "A core monitoring target is unreachable on ${stack.profile}."
      ''
    ];
  };
}
