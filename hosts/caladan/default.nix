# Caladan - x86 Mini PC
# Local compute node for AI workflows
{
  config,
  inputs,
  pkgs,
  ...
}:

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

  # Secrets: LITELLM_API_KEY is decrypted from secrets/caladan.yaml at
  # activation and rendered directly to ~/.hermes/.env (dotenv format, which
  # Hermes loads at startup via load_hermes_dotenv). This mirrors the ix
  # convention of writing each secret to the path its service reads.
  sops = {
    defaultSopsFormat = "yaml";
    defaultSopsFile = ../../secrets/caladan.yaml;
    age.keyFile = "/home/muad/.config/sops/age/keys.txt";

    secrets.LITELLM_API_KEY = {
      owner = "muad";
      group = "muad";
      mode = "0600";
    };

    templates."hermes.env" = {
      content = ''
        LITELLM_API_KEY=${config.sops.placeholder.LITELLM_API_KEY}
      '';
      path = "/home/muad/.hermes/.env";
      owner = "muad";
      group = "muad";
      mode = "0600";
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
    inputs.hermes-agent.packages.${pkgs.system}.default
  ];

  zramSwap = {
    enable = true;
    memoryPercent = 25;
  };

  system.stateVersion = "26.05";
}
