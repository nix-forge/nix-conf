{
  profile ? "home-server",
}:
{
  ...
}:
{
  services.prometheus.alertmanager = {
    enable = true;
    listenAddress = "127.0.0.1";
    port = 9093;
    configuration = {
      route = {
        receiver = "null";
        group_by = [ "alertname" ];
      };
      receivers = [
        {
          name = "null";
        }
      ];
    };
  };

  services.prometheus.alertmanagers = [
    {
      static_configs = [
        { targets = [ "127.0.0.1:9093" ]; }
      ];
    }
  ];
}
