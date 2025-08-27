# Services module - provides various service configurations
{ config, lib, pkgs, ... }:

with lib;
let cfg = config.modules.services;
in {
  options.modules.services = {
    docker.enable = mkBoolOpt false;
    nginx.enable = mkBoolOpt false;
    postgresql.enable = mkBoolOpt false;
    redis.enable = mkBoolOpt false;
    tailscale.enable = mkBoolOpt false;
    monitoring.enable = mkBoolOpt false;
  };

  config = mkMerge [
    (mkIf cfg.docker.enable {
      virtualisation.docker = {
        enable = true;
        enableOnBoot = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
        };
      };

      users.users.francocalvo.extraGroups = [ "docker" ];

      environment.systemPackages = with pkgs; [
        docker-compose
      ];
    })

    (mkIf cfg.nginx.enable {
      services.nginx = {
        enable = true;
        recommendedGzipSettings = true;
        recommendedOptimisation = true;
        recommendedProxySettings = true;
        recommendedTlsSettings = true;
      };

      networking.firewall.allowedTCPPorts = [ 80 443 ];
    })

    (mkIf cfg.postgresql.enable {
      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_15;
        enableTCPIP = true;
        authentication = pkgs.lib.mkOverride 10 ''
          local all all trust
          host all all 127.0.0.1/32 trust
          host all all ::1/128 trust
        '';
      };
    })

    (mkIf cfg.redis.enable {
      services.redis.servers."" = {
        enable = true;
        port = 6379;
        bind = "127.0.0.1";
      };
    })

    (mkIf cfg.tailscale.enable {
      services.tailscale.enable = true;
      networking.firewall = {
        checkReversePath = "loose";
        trustedInterfaces = [ "tailscale0" ];
        allowedUDPPorts = [ config.services.tailscale.port ];
      };
    })

    (mkIf cfg.monitoring.enable {
      services.prometheus = {
        enable = true;
        port = 9090;
        exporters = {
          node = {
            enable = true;
            enabledCollectors = [ "systemd" ];
            port = 9100;
          };
        };
        scrapeConfigs = [
          {
            job_name = "node";
            static_configs = [{
              targets = [ "localhost:${toString config.services.prometheus.exporters.node.port}" ];
            }];
          }
        ];
      };

      services.grafana = {
        enable = true;
        settings = {
          server = {
            http_addr = "127.0.0.1";
            http_port = 3000;
          };
        };
      };

      networking.firewall.allowedTCPPorts = [ 3000 9090 ];
    })
  ];
}
