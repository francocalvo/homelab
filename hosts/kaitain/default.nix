# Kaitain - ARM64 VPN Server
# The Imperial capital - controls access to the network
{ config, lib, pkgs, modulesPath, ... }:

{
  # imports = [ ./disko.nix ];

  services = { openssh = { enable = true; }; };

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
    oci-containers.backend = [ "podman" ];
  };

  # Enable container name DNS for podman networks
  networking.firewall.interfaces = let
    matchAll =
      if !config.networking.nftables.enable then "podman+" else "podman*";
  in { "${matchAll}" = { allowedUDPPorts = [ 53 ]; }; };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
  };

  environment.systemPackages = with pkgs; [ neovim ];
}
