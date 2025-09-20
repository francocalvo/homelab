# Auto-generated using compose2nix v0.3.3-pre.
{ pkgs, lib, config, ... }:

{
  # Containers
  virtualisation.oci-containers.containers."jellyfin" = {
    image = "lscr.io/linuxserver/jellyfin:latest";
    environment = {
      "JELLYFIN_PublishedServerUrl" = "https://jellyfin.calvo.dev";
      "PGID" = "1000";
      "PUID" = "1000";
      "TZ" = "America/Argentina/Cordoba";
    };
    volumes = [
      "/mnt/arrakis/jellyfin:/config:rw"
      "/mnt/media/movies:/data/movies:rw"
      "/mnt/media/series:/data/series:rw"
    ];
    ports = [
      "8096:8096/tcp"
      "8920:8920/tcp"
      "7359:7359/udp"
      "1900:1900/udp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=jellyfin"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-jellyfin" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-ix_default.service"
    ];
    requires = [
      "podman-network-ix_default.service"
    ];
    partOf = [
      "podman-compose-ix-root.target"
    ];
    wantedBy = [
      "podman-compose-ix-root.target"
    ];
  };
}
