# Kaitain - ARM64 VPN Server
# The Imperial capital - controls access to the network
{
  config,
  lib,
  pkgs,
  modulesPath,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix
    ./container-networking.nix

    ./container-swag.nix
    ./container-wg.nix
    ./container-speedtest.nix
  ];

  services = {
    openssh = {
      enable = true;
    };
  };

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
  networking.firewall.interfaces =
    let
      matchAll = if !config.networking.nftables.enable then "podman+" else "podman*";
    in
    {
      "${matchAll}" = {
        allowedUDPPorts = [ 53 ];
      };
    };

  boot.kernelModules = [ "ip6table_nat" ];

  # NFS mount configuration
  fileSystems."/mnt/arrakis" = {
    device = "192.168.1.251:/mnt/arrakis/kaitain";
    fsType = "nfs";
    options = [
      "rw"
      "hard"
      "intr"
    ];
  };

  powerManagement = {
    enable = true;
    cpuFreqGovernor = "performance";
  };

  # User configuration
  users.users.kaitain = {
    isNormalUser = true;
    uid = 1000;
    group = "kaitain";
    home = "/home/kaitain";
    createHome = true;
    extraGroups = [
      "wheel"
      "podman"
      "docker"
    ];
  };

  networking.firewall.allowedTCPPorts = [
    5201 # iperf3
  ];

  users.groups.kaitain = {
    gid = 1000;
  };

  environment.systemPackages = with pkgs; [
    neovim
    librecast
    wireguard-tools
  ];

  system.stateVersion = "25.05";
}
