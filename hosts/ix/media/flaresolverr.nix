{
  lib,
  ...
}:

{
  virtualisation.oci-containers.containers."flaresolverr" = {
    image = "ghcr.io/flaresolverr/flaresolverr:latest";
    environment = {
      "LOG_LEVEL" = "info";
      "TZ" = "America/Argentina/Cordoba";
    };
    ports = [
      "8191:8191/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=flaresolverr"
      "--network=ix_default"
      "--security-opt=no-new-privileges"
    ];
  };

  systemd.services."podman-flaresolverr" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-ix_default.service" ];
    requires = [ "podman-network-ix_default.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };
}
