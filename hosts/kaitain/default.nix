# Kaitain - ARM64 VPN Server
# The Imperial capital - controls access to the network
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    ./disko.nix
  ];

  # Disable conflicting modules from nixpkgs
  # disabledModules = [
  #   "system/boot/loader/raspberrypi"
  #   "system/boot/loader/raspberrypi/raspberrypi-builder.sh"
  # ];

  # networking = {
  #   hostName = "kaitain";
  #   enableIPv6 = true;
  #   firewall = {
  #     enable = true;
  #     allowedTCPPorts = [ 
  #       80    # HTTP
  #       443   # HTTPS
  #       51820 # WireGuard
  #       51821 # WireGuard UI
  #     ];
  #     allowedUDPPorts = [
  #       51820 # WireGuard
  #       51821 # WireGuard UI
  #     ];
  #   };
  # };

  # services = {
  #   openssh = {
  #     enable = true;
  #     settings = {
  #       PasswordAuthentication = false;
  #       KbdInteractiveAuthentication = false;
  #     };
  #   };
  #
  #   hardware.argonone.enable = true;
  # };

  # modules = {
  #   editor = {
  #     neovim.enable = true;
  #   };
  #   services = {
  #     docker.enable = true;
  #   };
  # };

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

  # Additional packages for VPN/proxy management
  # environment.systemPackages = with pkgs; [
    # libraspberrypi
    # wireguard-tools
    # htop
    # iotop
    # tcpdump
    # nmap
  # ];
}
