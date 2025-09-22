# Auto-generated using compose2nix v0.3.3-pre.
{ pkgs, lib, config, ... }:

{

  # Containers
  virtualisation.oci-containers.containers."nextcloud-aio-mastercontainer" = {
    image = "ghcr.io/nextcloud-releases/all-in-one:latest";
    environment = {
      "APACHE_IP_BINDING" = "0.0.0.0";
      "APACHE_PORT" = "11000";
      "NEXTCLOUD_DATADIR" = "/mnt/nextcloud";
      "WATCHTOWER_DOCKER_SOCKET_PATH" = "/run/podman/podman.sock";
    };
    volumes = [
      "nextcloud_aio_mastercontainer:/mnt/docker-aio-config:rw"
      "/var/run/docker.sock:/var/run/docker.sock:ro"
    ];
    ports = [
      "8080:8080/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=nextcloud-aio-mastercontainer"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-nextcloud-aio-mastercontainer" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-ix_default.service"
      "podman-volume-nextcloud_aio_mastercontainer.service"
    ];
    requires = [
      "podman-network-ix_default.service"
      "podman-volume-nextcloud_aio_mastercontainer.service"
    ];
    partOf = [
      "podman-compose-ix-root.target"
    ];
    wantedBy = [
      "podman-compose-ix-root.target"
    ];
  };

  # Volumes
  systemd.services."podman-volume-nextcloud_aio_mastercontainer" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      podman volume inspect nextcloud_aio_mastercontainer || podman volume create nextcloud_aio_mastercontainer
    '';
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

}
