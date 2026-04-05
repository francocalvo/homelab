{
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."bazarr" = {
    image = "lscr.io/linuxserver/bazarr:latest";
    environment = {
      "PGID" = "1000";
      "PUID" = "1000";
      "TZ" = "America/Argentina/Cordoba";
    };
    volumes = [
      "/home/muad/containers/media/bazarr:/config:rw"
      "/mnt/media:/data:rw"
    ];
    ports = [
      "6767:6767/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=bazarr"
      "--network=ix_default"
    ];
  };

  systemd.services."podman-bazarr" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-ix_default.service" ];
    requires = [ "podman-network-ix_default.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };
}
