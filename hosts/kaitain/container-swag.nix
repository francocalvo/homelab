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
    "bag"         # wallabag
    "overleaf"    # overleaf
  ];
  subdomains = lib.concatStringsSep ", " services;
  ixHost = "192.168.0.4";
  overleafPort = "8084";
in
{
  environment.etc."swag/proxy-confs/subdomains/overleaf.subdomain.conf".text = ''
    server {
        listen 443 ssl;
        listen [::]:443 ssl;

        server_name overleaf.*;

        include /config/nginx/ssl.conf;

        client_max_body_size 0;

        location / {
            include /config/nginx/proxy.conf;
            include /config/nginx/resolver.conf;
            set $upstream_app ${ixHost};
            set $upstream_port ${overleafPort};
            set $upstream_proto http;
            proxy_pass $upstream_proto://$upstream_app:$upstream_port;

            proxy_read_timeout 3600;
            proxy_send_timeout 3600;
            proxy_buffering off;
        }
    }
  '';

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
      "SUBDOMAINS" = "wildcard";
      "TZ" = "America/Argentina/Cordoba";
      "URL" = "calvo.dev";
      "VALIDATION" = "dns";
    };
    volumes = [
      "/mnt/arrakis/swag:/config:rw"
      "/etc/swag/proxy-confs/subdomains/overleaf.subdomain.conf:/config/nginx/proxy-confs/subdomains/overleaf.subdomain.conf:ro"
    ];
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
