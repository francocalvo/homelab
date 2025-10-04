# Default NixOS configuration shared across all hosts
{ config, lib, pkgs, ... }:

{
  imports = lib.my.mapModulesRec' ./modules import;

  nix = {
    settings = {
      experimental-features = [ "nix-command" "flakes" ];
      auto-optimise-store = true;
    };
    gc = {
      automatic = true;
      dates = "weekly";
      options = "--delete-older-than 7d";
    };
  };

  # Basic networking
  networking = {
    networkmanager.enable = true;
    firewall.enable = true;
  };

  # Time zone and internationalization
  time.timeZone = "America/Argentina/Buenos_Aires";
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    useXkbConfig = true;
    # keyMap = "es";
  };

  # Security
  security = {
    sudo.wheelNeedsPassword = false;
    polkit.enable = true;
  };

  # Common packages available on all hosts
  environment.systemPackages = with pkgs; [
    git
    neovim
    curl
    wget
    htop
    tree
    unzip
    file
    podman-compose
  ];

  # Users configuration
  users = {
    defaultUserShell = pkgs.zsh;
    users.muad = {
      isNormalUser = true;
      extraGroups = [ "wheel" "networkmanager" ];
      openssh.authorizedKeys.keys = [
        # Add your SSH public key here
        # "ssh-rsa AAAAB3NzaC1yc2E... your-email@example.com"
      ];
    };
  };

  programs.git = {
    enable = true;
    config = {
      user = {
        email = "dev@francocalvo.ar";
        name = "francocalvo";
      };
    };
  };

  programs.zsh.enable = true;
}
