# Desktop module - provides desktop environment configurations
{ config, lib, pkgs, ... }:

with lib;
let cfg = config.modules.desktop;
in {
  options.modules.desktop = {
    enable = mkBoolOpt false;
    environment = mkOption {
      type = types.enum [ "gnome" "kde" "i3" "hyprland" ];
      default = "gnome";
      description = "Desktop environment to use";
    };
    audio.enable = mkBoolOpt true;
    bluetooth.enable = mkBoolOpt false;
  };

  config = mkIf cfg.enable (mkMerge [
    {
      # X11 windowing system
      services.xserver = {
        enable = true;
        xkb = {
          layout = "us";
          variant = "";
        };
      };

      # Display manager
      services.displayManager.sddm.enable = mkDefault true;

      # Common desktop packages
      environment.systemPackages = with pkgs; [
        firefox
        chromium
        thunderbird
        libreoffice
        vlc
        gimp
        # File managers
        nautilus
        # Archive tools
        file-roller
        # Image viewers
        eog
      ];

      # Fonts
      fonts.packages = with pkgs; [
        noto-fonts
        noto-fonts-cjk
        noto-fonts-emoji
        liberation_ttf
        fira-code
        fira-code-symbols
      ];
    }

    # GNOME
    (mkIf (cfg.environment == "gnome") {
      services.xserver.desktopManager.gnome.enable = true;
      services.displayManager.gdm.enable = true;
      services.displayManager.sddm.enable = mkForce false;
      
      environment.gnome.excludePackages = (with pkgs; [
        gnome-photos
        gnome-tour
      ]) ++ (with pkgs.gnome; [
        cheese # webcam tool
        gnome-music
        epiphany # web browser
        geary # email reader
        totem # video player
        tali # poker game
        iagno # go game
        hitori # sudoku game
        atomix # puzzle game
      ]);
    })

    # KDE Plasma
    (mkIf (cfg.environment == "kde") {
      services.xserver.desktopManager.plasma5.enable = true;
      services.displayManager.sddm.enable = true;
    })

    # i3 window manager
    (mkIf (cfg.environment == "i3") {
      services.xserver = {
        windowManager.i3.enable = true;
        displayManager.defaultSession = "none+i3";
      };
      
      environment.systemPackages = with pkgs; [
        dmenu
        i3status
        i3lock
        rofi
        picom
        feh
        alacritty
      ];
    })

    # Hyprland (Wayland)
    (mkIf (cfg.environment == "hyprland") {
      programs.hyprland.enable = true;
      services.displayManager.sddm.enable = true;
      
      environment.systemPackages = with pkgs; [
        waybar
        wofi
        alacritty
        swaylock
        wl-clipboard
        grim
        slurp
      ];
    })

    # Audio
    (mkIf cfg.audio.enable {
      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        alsa.support32Bit = true;
        pulse.enable = true;
        jack.enable = true;
      };
    })

    # Bluetooth
    (mkIf cfg.bluetooth.enable {
      hardware.bluetooth = {
        enable = true;
        powerOnBoot = true;
      };
      services.blueman.enable = true;
    })
  ]);
}
