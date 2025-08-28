# Kaitain - ARM64 VPN Server
# The Imperial capital - controls access to the network
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [ ./disko.nix ];

  services = {
    openssh = { enable = true; };
  };

  # ARM-specific optimizations
  # nix.settings = {
  #   max-jobs = lib.mkDefault 2;
  #   cores = lib.mkDefault 2;
  # };
  #
  # powerManagement = {
  #   enable = true;
  #   cpuFreqGovernor = "performance";
  # };

  environment.systemPackages = with pkgs; [
    neovim
    # libraspberrypi
    # wireguard-tools
    # htop
    # iotop
    # tcpdump
    # nmap
  ];
}
