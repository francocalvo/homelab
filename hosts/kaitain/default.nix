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

  sops = {
    defaultSopsFormat = "yaml";
    defaultSopsFile = ../../secrets/kaitain.yaml;
    age.keyFile = "/home/muad/.config/sops/age/keys.txt";

    secrets = {
      speedtest_env = {
        path = "/mnt/arrakis/speedtest-tracker/.env";
      };
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
  networking.firewall.allowedTCPPorts = [
    5201 # iperf3
  ];

  environment.systemPackages = with pkgs; [ neovim ];

  users.users.muad = {
    isNormalUser = true;
    uid = 1000;
    group = "muad";
    home = "/home/muad";
    createHome = true;
    extraGroups = [
      "wheel"
      "podman"
      "docker"
    ];
  };

  users.groups.muad = {
    gid = 1000;
  };

  system.stateVersion = "25.05";
}
