{
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."radarr" = {
    image = "lscr.io/linuxserver/radarr:latest";
    environment = {
      "PGID" = "1000";
      "PUID" = "1000";
      "TZ" = "America/Argentina/Cordoba";
    };
    volumes = [
      "/home/muad/containers/media/radarr:/config:rw"
      "/mnt/media:/data:rw"
    ];
    ports = [
      "7878:7878/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=radarr"
      "--network=ix_default"
    ];
  };

  systemd.services."podman-radarr" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-ix_default.service" ];
    requires = [ "podman-network-ix_default.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };
}
