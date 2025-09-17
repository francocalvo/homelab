# IX - x86 Mini PC
# Small form factor compute node
{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [ ./disko-config.nix ];

  homelab.podman = {
    enable = true;
    networking = {
      enable = true;
      hostName = "ix";
    };
  };

  disko.devices.disk.main.device = "/dev/sda";

  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
  };

  # Hardware-specific settings
  hardware = {
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };

  # Network configuration
  networking = {
    hostName = "ix";
  };

  services = {
    openssh.enable = true;
  };

  # NFS mount configuration
  fileSystems."/mnt/arrakis" = {
    device = "192.168.1.251:/mnt/arrakis/ix";
    fsType = "nfs";
    options = [
      "rw"
      "hard"
      "intr"
    ];
  };

  # User configuration
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

  environment.systemPackages = with pkgs; [ neovim ];
}
