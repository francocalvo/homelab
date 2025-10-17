# Auto-generated using compose2nix v0.3.2-pre.
{
  pkgs,
  lib,
  config,
  ...
}:

let
  services = [
    "vpn"         # wg-easy
    "jellyfin"    # jellyfin
    "iperf"       # speedtest-tracker
    "cloud"       # nextcloud
  ];
  subdomains = lib.concatStringsSep ", " services;
in
{

  # Containers
  virtualisation.oci-containers.containers."swag" = {
    image = "lscr.io/linuxserver/swag";
    environment = {
      "CERTPROVIDER" = "letsencrypt";
      "DNSPLUGIN" = "cloudflare";
      "EMAIL" = "dns@fjc.ar";
      "ONLY_SUBDOMAINS" = "false";
      "PGID" = "1000";
      "PUID" = "1000";
      "STAGING" = "false";
      "SUBDOMAINS" = subdomains;
      "TZ" = "America/Argentina/Cordoba";
      "URL" = "calvo.dev";
      "VALIDATION" = "http";
    };
    volumes = [ "/mnt/arrakis/swag:/config:rw" ];
    ports = [
      "443:443/tcp"
      "80:80/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--network-alias=swag"
      "--network=kaitain_default"
    ];
  };
  systemd.services."podman-swag" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [ "podman-network-kaitain_default.service" ];
    requires = [ "podman-network-kaitain_default.service" ];
    partOf = [ "podman-compose-kaitain-root.target" ];
    wantedBy = [ "podman-compose-kaitain-root.target" ];
  };

  # Ensure swag directory exists
  systemd.tmpfiles.rules = [
    "d /mnt/arrakis/swag 0755 1000 1000 -"
  ];
}
