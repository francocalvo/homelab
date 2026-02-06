# Immich - Self-hosted photo and video backup solution
# https://immich.app/
{
  pkgs,
  lib,
  config,
  ...
}:

let
  immichVersion = "release";
in
{
  # Immich Server Container
  virtualisation.oci-containers.containers."immich-server" = {
    image = "ghcr.io/immich-app/immich-server:${immichVersion}";
    environmentFiles = [ "/mnt/arrakis/immich/.env" ];
    volumes = [
      "/mnt/arrakis/immich/library:/data:rw,z"
      "/etc/localtime:/etc/localtime:ro"
    ];
    ports = [ "2283:2283/tcp" ];
    dependsOn = [
      "immich-redis"
      "immich-database"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=immich-server"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-immich-server" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [ "podman-network-ix_default.service" ];
    requires = [
      "podman-network-ix_default.service"
      "mnt-arrakis.mount"
    ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  # Immich Machine Learning Container
  virtualisation.oci-containers.containers."immich-machine-learning" = {
    image = "ghcr.io/immich-app/immich-machine-learning:${immichVersion}";
    environmentFiles = [ "/mnt/arrakis/immich/.env" ];
    volumes = [
      "/home/muad/containers/immich/model-cache:/cache:rw,z"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=immich-machine-learning"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-immich-machine-learning" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [ "podman-network-ix_default.service" ];
    requires = [
      "podman-network-ix_default.service"
      "mnt-arrakis.mount"
    ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  # Redis (Valkey) Container
  virtualisation.oci-containers.containers."immich-redis" = {
    image = "docker.io/valkey/valkey:9@sha256:546304417feac0874c3dd576e0952c6bb8f06bb4093ea0c9ca303c73cf458f63";
    log-driver = "journald";
    extraOptions = [
      "--network-alias=redis"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-immich-redis" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [ "podman-network-ix_default.service" ];
    requires = [
      "podman-network-ix_default.service"
      "mnt-arrakis.mount"
    ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  # Postgres Database Container
  virtualisation.oci-containers.containers."immich-database" = {
    image = "ghcr.io/immich-app/postgres:14-vectorchord0.4.3-pgvectors0.2.0@sha256:bcf63357191b76a916ae5eb93464d65c07511da41e3bf7a8416db519b40b1c23";
    environmentFiles = [ "/mnt/arrakis/immich/.env" ];
    environment = {
      "POSTGRES_INITDB_ARGS" = "--data-checksums";
    };
    volumes = [
      "/home/muad/containers/immich/postgres:/var/lib/postgresql/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=database"
      "--network=ix_default"
      "--shm-size=128mb"
    ];
  };
  systemd.services."podman-immich-database" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [ "podman-network-ix_default.service" ];
    requires = [
      "podman-network-ix_default.service"
      "mnt-arrakis.mount"
    ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  # Ensure directories exist
  systemd.tmpfiles.rules = [
    "d /mnt/arrakis/immich/library 0755 1000 1000 -"
    "d /mnt/arrakis/immich/import 0755 1000 1000 -"
    "d /home/muad/containers/immich/model-cache 0755 1000 1000 -"
    "d /home/muad/containers/immich/postgres 0755 1000 1000 -"
  ];
}
