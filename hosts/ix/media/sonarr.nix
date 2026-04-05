{
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."sonarr" = {
    image = "lscr.io/linuxserver/sonarr:latest";
    environment = {
      "PGID" = "1000";
      "PUID" = "1000";
      "TZ" = "America/Argentina/Cordoba";
    };
    volumes = [
      "/home/muad/containers/media/sonarr:/config:rw"
      "/mnt/media:/data:rw"
    ];
    ports = [
      "8989:8989/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=sonarr"
      "--network=ix_default"
    ];
  };

  systemd.services."podman-sonarr" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-ix_default.service" ];
    requires = [ "podman-network-ix_default.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };
}
