# IX - x86 Mini PC
# Small form factor compute node
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

{
  imports = [
    ./hardware-configuration.nix

    # Containers
    ./container-jellyfin.nix
    ./container-nextcloud.nix
    ./container-git-bridge.nix
    ./container-overleaf.nix
    ./container-wallabag.nix

    # VMs
    ./vm-clawdbot.nix
  ];

  sops = {
    defaultSopsFormat = "yaml";
    defaultSopsFile = ../../secrets/ix.yaml;
    age.keyFile = "/home/muad/.config/sops/age/keys.txt";

    secrets = {
      nextcloud_env = {
        path = "/mnt/arrakis/nextcloud/.env";
      };

      wallabag_env = {
        path = "/mnt/arrakis/wallabag/.env";
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

  # All ix_default containers depend on NFS mounts via their network service.
  systemd.services."podman-network-ix_default".unitConfig.RequiresMountsFor = "/mnt/arrakis /mnt/media /mnt/nextcloud";

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
    extraHosts = ''
      192.168.0.100 calvo.dev
      192.168.0.100 bag.calvo.dev
      192.168.0.100 cloud.calvo.dev
      192.168.0.100 creditscan.calvo.dev
      192.168.0.100 csapi.calvo.dev
      192.168.0.100 fif.calvo.dev
      192.168.0.100 iperf.calvo.dev
      192.168.0.100 jellyfin.calvo.dev
      192.168.0.100 nhook.calvo.dev
      192.168.0.100 overleaf.calvo.dev
      192.168.0.100 vpn.calvo.dev
    '';
    firewall.allowedTCPPorts = [
      5000  # overleaf git bridge
      8765  # nhook webhook server
      18437 # fifoteca backend
      53172 # fifoteca frontend
    ];
  };

  services = {
    openssh.enable = true;
  };

  # NFS readiness gate — wait until the NAS is actually reachable before
  # systemd attempts any NFS mount.  network-online.target alone is not a
  # strong enough signal on this host (see ERR.md).
  systemd.services.nfs-nas-wait = {
    description = "Wait for NAS at 192.168.0.251";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    before = [
      "mnt-arrakis.mount"
      "mnt-media.mount"
      "mnt-nextcloud.mount"
    ];
    requiredBy = [
      "mnt-arrakis.mount"
      "mnt-media.mount"
      "mnt-nextcloud.mount"
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      TimeoutStartSec = "120";
    };
    path = [ pkgs.iproute2 ];
    script = ''
      until ip route get 192.168.0.251 >/dev/null 2>&1; do
        sleep 1
      done
      until (echo > /dev/tcp/192.168.0.251/2049) 2>/dev/null; do
        sleep 1
      done
    '';
  };

  # NFS mount configuration
  fileSystems."/mnt/arrakis" = {
    device = "192.168.0.251:/mnt/arrakis/ix";
    fsType = "nfs";
    options = [
      "rw"
      "hard"
      "intr"
      "_netdev"
      "nofail"
    ];
  };

  fileSystems."/mnt/media" = {
    device = "192.168.0.251:/mnt/arrakis/media";
    fsType = "nfs";
    options = [
      "rw"
      "hard"
      "intr"
      "_netdev"
      "nofail"
    ];
  };

  fileSystems."/mnt/nextcloud" = {
    device = "192.168.0.251:/mnt/arrakis/nextcloud";
    fsType = "nfs";
    options = [
      "rw"
      "hard"
      "intr"
      "nolock"
      "_netdev"
      "nofail"
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

  environment.systemPackages = with pkgs; [
    neovim
    sops
    tmux
    inputs.claude-code.packages.${pkgs.system}.default
  ];
  system.stateVersion = "25.05";

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  nix.settings.extra-platforms = config.boot.binfmt.emulatedSystems;
}
