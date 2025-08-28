# Kaitain - ARM64 VPN Server
# The Imperial capital - controls access to the network
{ config, lib, pkgs, modulesPath, ... }:

{
  # imports = [ ./disko.nix ];

  services = { openssh = { enable = true; }; };

  virtualisation = {
    docker = {
      enable = true;
      rootless.enable = true;
      autoPrune = {
        enable = true;
        dates = "weekly";
        flags = [ "--all" ];
      };
    };
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
  };

  environment.systemPackages = with pkgs; [
    neovim
    libraspberrypi
    wireguard-tools
    htop
    iotop
    tcpdump
    nmap
  ];
}
