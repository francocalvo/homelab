# Caladan - x86 Mini PC
# Local compute node for AI workflows
{ pkgs, ... }:

{
  imports = [
    ./hardware-configuration.nix
  ];

  boot.loader = {
    systemd-boot.enable = true;
    efi.canTouchEfiVariables = true;
  };

  hardware.enableRedistributableFirmware = true;

  networking.hostName = "caladan";

  services = {
    fstrim.enable = true;
    fwupd.enable = true;
    openssh = {
      enable = true;
      settings = {
        KbdInteractiveAuthentication = false;
        PasswordAuthentication = false;
        PermitRootLogin = "no";
      };
    };
    tailscale = {
      enable = true;
      openFirewall = true;
    };
  };

  # Keep the container runtime ready without deploying workloads yet.
  homelab.podman.enable = true;

  users = {
    groups.muad.gid = 1000;
    users.muad = {
      uid = 1000;
      group = "muad";
      home = "/home/muad";
      createHome = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICPY19qVNxrSt4Ulb1C6L661wa6h0+GV+tX3HjsmUonl"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPaFk0BPHPq4TwAhBcs6fHhoztmpbO+IQrpvxn4xsMDO"
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    age
    fd
    fzf
    jq
    lsof
    ncdu
    ripgrep
    rsync
    sops
    tmux
    yq-go
  ];

  system.stateVersion = "26.05";
}
