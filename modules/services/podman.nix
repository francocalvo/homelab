{ pkgs, lib, config, ... }:

with lib;

let
  cfg = config.homelab.podman;
in
{
  options.homelab.podman = {
    enable = mkEnableOption "Podman virtualization with docker compatibility";
  };

  config = mkIf cfg.enable {
    virtualisation = {
      podman = {
        enable = true;
        dockerSocket.enable = true;
        dockerCompat = true;
        autoPrune = {
          enable = true;
          dates = "weekly";
          flags = [ "--all" ];
        };
      };
      oci-containers.backend = "podman";
    };

    # Enable container name DNS for podman networks
    networking.firewall.interfaces = let
      matchAll =
        if !config.networking.nftables.enable then "podman+" else "podman*";
    in { "${matchAll}" = { allowedUDPPorts = [ 53 ]; }; };

    boot.kernelModules = [ "ip6table_nat" ];
  };
}