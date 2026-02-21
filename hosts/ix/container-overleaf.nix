{
  pkgs,
  lib,
  config,
  ...
}:

let
  overleaf_version = "5.5.1";
in
{
  # Overleaf Web Application
  virtualisation.oci-containers.containers."ix-overleaf" = {
    image = "sharelatex/sharelatex:${overleaf_version}";
    environment = {
      "OVERLEAF_APP_NAME" = "Overleaf";
      "OVERLEAF_LISTEN_IP" = "0.0.0.0";
      "OVERLEAF_PORT" = "80";
      "OVERLEAF_SITE_URL" = "https://overleaf.calvo.dev";
      "OVERLEAF_MONGO_URL" = "mongodb://mongo/sharelatex";
      "OVERLEAF_REDIS_HOST" = "redis";
      "OVERLEAF_SECURE_COOKIE" = "true";
    };
    volumes = [ "/mnt/arrakis/overleaf/data:/var/lib/overleaf:rw" ];
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
    "d /mnt/arrakis/overleaf/redis 0755 1000 1000 -"
  ];
}
