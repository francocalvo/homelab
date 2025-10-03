# Auto-generated using compose2nix v0.3.3-pre.
{
  pkgs,
  lib,
  config,
  ...
}:

{
  # Containers
  virtualisation.oci-containers.containers."speedtest-tracker" = {
    image = "lscr.io/linuxserver/speedtest-tracker:latest";
    environment = {
      "APP_KEY" = "$(cat ${config.sops.speedtest_app_key.path})";
      "DB_CONNECTION" = "sqlite";
      "PGID" = "1000";
      "PUID" = "1000";
    };
    volumes = [
      "/mnt/arrakis/speedtest-tracker:/config:rw"
    ];
    ports = [
      "8383:80/tcp"
      "8343:443/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=speedtest-tracker"
      "--network=kaitain_default"
    ];
  };
  systemd.services."podman-speedtest-tracker" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-kaitain_default.service"
    ];
    requires = [
      "podman-network-kaitain_default.service"
    ];
    partOf = [
      "podman-compose-kaitain-root.target"
    ];
    wantedBy = [
      "podman-compose-kaitain-root.target"
    ];
  };
}
