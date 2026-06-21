{
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."seerr" = {
    image = "ghcr.io/seerr-team/seerr:latest";
    environment = {
      "LOG_LEVEL" = "info";
      "PORT" = "5055";
      "TZ" = "America/Argentina/Cordoba";
    };
    volumes = [
      "/home/muad/containers/media/seerr:/app/config:rw"
    ];
    ports = [
      "5055:5055/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--init"
      "--network-alias=seerr"
      "--network=ix_default"
    ];
  };

  systemd.services."podman-seerr" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-ix_default.service" ];
    requires = [ "podman-network-ix_default.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };
}
