{
  pkgs,
  lib,
  config,
  ...
}:

let
  overleaf_version = "5.5.1";

  # Nix TeX Live scheme-full — all packages, deterministic, cached by nixpkgs.
  texlive = pkgs.texlive.combined.scheme-full;

  # Symlinks from /opt/texlive/bin/<binary> -> /nix/store/.../bin/<binary>
  # so the texlive tools appear in the container's PATH without modifying
  # the base sharelatex image.
  texliveLinks = pkgs.runCommand "texlive-links" { } ''
    mkdir -p $out/opt/texlive/bin
    for bin in ${texlive}/bin/*; do
      ln -s "$bin" "$out/opt/texlive/bin/$(basename "$bin")"
    done
  '';
in
{
  # Overleaf Web Application
  virtualisation.oci-containers.containers."ix-overleaf" = {
    image = "sharelatex/sharelatex:${overleaf_version}";
    environment = {
      "OVERLEAF_APP_NAME" = "Overleaf";
      "OVERLEAF_BEHIND_PROXY" = "true";
      "OVERLEAF_LISTEN_IP" = "0.0.0.0";
      "OVERLEAF_PORT" = "80";
      "OVERLEAF_TRUSTED_PROXY_IPS" = "192.168.1.100,127.0.0.1,::1";
      "OVERLEAF_SITE_URL" = "https://overleaf.calvo.dev";
      "OVERLEAF_MONGO_URL" = "mongodb://mongo/sharelatex";
      "OVERLEAF_REDIS_HOST" = "redis";
      # Prepend Nix texlive to PATH so latexmk / pdflatex are found.
      "PATH" = "/opt/texlive/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin";
      # NOTE: OVERLEAF_SECURE_COOKIE is intentionally not set.
      # The git-bridge connects internally via http://sharelatex and needs
      # cookies without the Secure flag. SWAG still provides HTTPS to browsers.
    };
    volumes = [
      "/mnt/arrakis/overleaf/data:/var/lib/overleaf:rw"
      # Bind-mount the Nix store so texlive binaries can find their deps.
      "/nix/store:/nix/store:ro"
      # Symlinks that put texlive binaries on the container's PATH.
      "${texliveLinks}/opt/texlive/bin:/opt/texlive/bin:ro"
    ];
    ports = [ "8084:80/tcp" ];
    dependsOn = [
      "ix-overleaf-mongo"
      "ix-overleaf-redis"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=sharelatex"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-overleaf" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-ix_default.service"
      "overleaf-mongo-init-rs.service"
    ];
    requires = [
      "podman-network-ix_default.service"
      "overleaf-mongo-init-rs.service"
    ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  # MongoDB Backend
  virtualisation.oci-containers.containers."ix-overleaf-mongo" = {
    image = "mongo:6.0";
    cmd = [
      "--replSet"
      "rs0"
      "--bind_ip_all"
    ];
    volumes = [
      "/mnt/arrakis/overleaf/mongo:/data/db:rw"
      "/mnt/arrakis/overleaf/mongo_config:/data/configdb:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=mongo"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-overleaf-mongo" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [ "podman-network-ix_default.service" ];
    requires = [ "podman-network-ix_default.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  # Redis Backend
  virtualisation.oci-containers.containers."ix-overleaf-redis" = {
    image = "redis:6.2";
    cmd = [
      "--appendonly"
      "yes"
    ];
    volumes = [ "/mnt/arrakis/overleaf/redis:/data:rw" ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=redis"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-overleaf-redis" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [ "podman-network-ix_default.service" ];
    requires = [ "podman-network-ix_default.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  # Overleaf needs MongoDB replica-set mode to support real-time updates.
  systemd.services.overleaf-mongo-init-rs = {
    description = "Initialize MongoDB replica set for Overleaf";
    after = [ "podman-ix-overleaf-mongo.service" ];
    requires = [ "podman-ix-overleaf-mongo.service" ];
    before = [ "podman-ix-overleaf.service" ];
    wantedBy = [ "podman-compose-ix-root.target" ];

    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.podman
    ];

    script = ''
      set -eu

      for i in $(seq 1 30); do
        if podman exec ix-overleaf-mongo mongosh --quiet --eval "db.adminCommand({ ping: 1 }).ok" | grep -q 1; then
          break
        fi
        sleep 2
      done

      podman exec ix-overleaf-mongo mongosh --quiet --eval '
        try {
          rs.status();
        } catch (err) {
          rs.initiate({
            _id: "rs0",
            members: [{ _id: 0, host: "mongo:27017" }]
          });
        }
      '
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /mnt/arrakis/overleaf 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/data 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/mongo 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/mongo_config 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/redis 0777 1000 1000 -"
  ];
}
