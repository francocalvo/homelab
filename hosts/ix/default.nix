# IX - x86 Mini PC
# Small form factor compute node
{
  config,
  lib,
  pkgs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix

    # Containers
    ./container-jellyfin.nix

    # inputs.sops-nix.nixosModules.sops-nix
  ];

  sops = {
    defaultSopsFormat = "yaml";
    defaultSopsFile = ../../secrets/secrets.yaml;
    age.keyFile = "/home/muad/.config/sops/age/keys.txt";

    secrets = {
      speedtest_app_key = {
        owner = config.users.users.muad.name;
      };
    };
  };

  homelab.podman = {
    enable = true;
    networking = {
      enable = true;
      hostName = "ix";
    };
  };

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

  fileSystems."/mnt/media" = {
    device = "192.168.1.251:/mnt/arrakis/media";
    fsType = "nfs";
    options = [
      "rw"
      "hard"
      "intr"
    ];
  };

  fileSystems."/mnt/nextcloud" = {
    device = "192.168.1.251:/mnt/arrakis/nextcloud";
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
  system.stateVersion = "25.05";

  boot.binfmt.emulatedSystems = ["aarch64-linux"];	
  nix.settings.extra-platforms = config.boot.binfmt.emulatedSystems;
}
