# x86_64 Linux host configuration
{ config, lib, pkgs, modulesPath, ... }:

{
  imports = [
    # Include the default configuration
    # Note: This will be automatically included by the mkHost function
    
    # Hardware configuration (you'll need to generate this)
    # ./hardware-configuration.nix
  ];

  # Boot configuration for x86_64
  boot = {
    loader = {
      systemd-boot.enable = true;
      efi.canTouchEfiVariables = true;
    };
    # Add any x86_64 specific kernel modules or options
    kernelModules = [ ];
  };

  # Hardware-specific settings
  hardware = {
    cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
    # Or for AMD:
    # cpu.amd.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };

  # Network configuration
  networking = {
    hostName = "x86-host";
    # Add any specific networking configuration
  };

  # Services specific to this host
  services = {
    openssh = {
      enable = true;
      settings = {
        PasswordAuthentication = false;
        KbdInteractiveAuthentication = false;
      };
    };
    
    # Add other services as needed
  };

  # Desktop environment (if this is a desktop machine)
  # Uncomment if you want a GUI
  # services.xserver = {
  #   enable = true;
  #   displayManager.gdm.enable = true;
  #   desktopManager.gnome.enable = true;
  # };

  # Enable specific modules for this host
  modules = {
    editor = {
      neovim.enable = true;
    };
    services = {
      # Enable services as needed
    };
  };
}
