{
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."qbittorrent" = {
    image = "lscr.io/linuxserver/qbittorrent:latest";
    environment = {
      "PGID" = "1000";
      "PUID" = "1000";
      "TZ" = "America/Argentina/Cordoba";
      "WEBUI_PORT" = "8080";
    };
    volumes = [
      "/home/muad/containers/media/qbittorrent:/config:rw"
      "/mnt/media:/data:rw"
    ];
    ports = [
      "8085:8080/tcp"
      "6881:6881/tcp"
      "6881:6881/udp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=qbittorrent"
      "--network=ix_default"
    ];
  };

  systemd.services."podman-qbittorrent" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-ix_default.service" ];
    requires = [ "podman-network-ix_default.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };
}
