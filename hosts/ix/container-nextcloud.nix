{
  pkgs,
  lib,
  config,
  ...
}:

let
  inherit (pkgs) lib;
  nextcloud_version = "32.0.0-fpm";
in
{

  # Nextloud Application Server
  virtualisation.oci-containers.containers."ix-app" = {
    image = "nextcloud:${nextcloud_version}";
    environmentFiles = [
      "/mnt/arrakis/nextcloud/.env"
    ];
    volumes = [
      "/home/muad/containers/nextcloud/data:/var/www/html:rw,z"
      "/mnt/nextcloud:/var/www/html/data:rw,z"
    ];
    dependsOn = [
      "ix-db"
      "ix-redis"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=app"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-app" = {
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

  # Cron Job Container
  virtualisation.oci-containers.containers."ix-cron" = {
    image = "nextcloud:${nextcloud_version}";
    volumes = [
      "/home/muad/containers/nextcloud/data:/var/www/html:rw,z"
      "/mnt/nextcloud:/var/www/html/data:rw,z"
    ];
    dependsOn = [
      "ix-db"
      "ix-redis"
    ];
    log-driver = "journald";
    extraOptions = [
      "--entrypoint=[\"/cron.sh\"]"
      "--network-alias=cron"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-cron" = {
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

  # Database Container
  virtualisation.oci-containers.containers."ix-db" = {
    image = "postgres:18";
    environmentFiles = [
      "/mnt/arrakis/nextcloud/.env"
    ];
    volumes = [
      "/home/muad/containers/nextcloud/database:/var/lib/postgresql:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=db"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-db" = {
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

  # Imaginary Container
  virtualisation.oci-containers.containers."ix-imaginary" = {
    image = "nextcloud/aio-imaginary:latest";
    environmentFiles = [
      "/mnt/arrakis/nextcloud/.env"
    ];
    dependsOn = [
      "ix-app"
    ];
    log-driver = "journald";
    extraOptions = [
      "--cap-add=SYS_NICE"
      "--network-alias=imaginary"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-imaginary" = {
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

  # Notify Push Container
  virtualisation.oci-containers.containers."ix-notify_push" = {
    image = "nextcloud:${nextcloud_version}";
    environment = {
      "NEXTCLOUD_URL" = "http://webserver";
      "PORT" = "7867";
    };
    volumes = [
      "/home/muad/containers/nextcloud/data:/var/www/html:ro,z"
      "/mnt/nextcloud:/var/www/html/data:ro,z"
    ];
    dependsOn = [
      "ix-app"
    ];
    log-driver = "journald";
    extraOptions = [
      "--entrypoint=[\"sh\", \"-c\", \"for i in $(seq 1 60); do
    curl -fsS http://webserver/index.php/login >/dev/null 2>&1 && break
    echo \"notify_push: waiting for webserver... ()\"
    sleep 2
  done
  exec /var/www/html/custom_apps/notify_push/bin/x86_64/notify_push --port \"7867\" /var/www/html/config/config.php
  \"]"
      "--network-alias=notify_push"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-notify_push" = {
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

  # Redis Container
  virtualisation.oci-containers.containers."ix-redis" = {
    image = "redis:alpine";
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=redis-cli ping | grep PONG"
      "--health-interval=30s"
      "--health-retries=3"
      "--health-start-period=10s"
      "--health-timeout=3s"
      "--network-alias=redis"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-redis" = {
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

  # Nginx Webserver Container
  virtualisation.oci-containers.containers."ix-webserver" = {
    image = "nginx:alpine-slim";
    volumes = [
      "/home/muad/containers/nextcloud/data:/var/www/html:ro,z"
      "/mnt/arrakis/nextcloud/nginx.conf:/etc/nginx/nginx.conf:ro,z"
      "/mnt/nextcloud:/var/www/html/data:ro,z"
    ];
    ports = [
      "8080:80/tcp"
    ];
    dependsOn = [
      "ix-app"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=webserver"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-webserver" = {
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
