# francocalvo - dev@francocalvo.ar
# This is my Nix flake that builds my homelab NixOS setup.
# Supports multiple architectures (x86_64 and ARM) with reusable modules.
#
# Structure:
#  flake.nix *
#   ├─ ./hosts/          # Host-specific configurations
#   ├─ ./modules/        # Reusable modules (editor, services, etc.)
#   └─ ./lib/            # Custom library functions

{
  description = "Homelab NixOS configurations with multi-architecture support";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    nixos-raspberrypi = {
      url = "github:nvmd/nixos-raspberrypi/main";
    };
    disko = {
      # the fork is needed for partition attributes support
      url = "github:nvmd/disko/gpt-attrs";
      # url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixos-raspberrypi/nixpkgs";
    };
  };

  outputs =
    inputs@{
      self,
      nixpkgs,
      nixos-raspberrypi,
      disko,
      ...
    }:
    let
      # Create the base library first (without system-specific pkgs)
      lib = nixpkgs.lib.extend (
        final: prev: {
          my = import ./lib {
            inherit inputs;
            lib = final;
            pkgs = nixpkgs.legacyPackages.x86_64-linux;
          };
        }
      );

      # Now we can use the system utilities from our lib
      inherit (lib.my) mapModulesRec mapHosts;

    in
    {
      lib = lib.my;

      nixosModules = mapModulesRec ./modules import;

      nixosConfigurations = {
        x86-host = lib.my.mkHost ./hosts/x86-host.nix { system = "x86_64-linux"; };
        kaitain = nixos-raspberrypi.lib.nixosSystem {
          specialArgs = inputs;
          modules = [
            (
              {
                config,
                pkgs,
                lib,
                nixos-raspberrypi,
                disko,
                ...
              }:
              {
                imports = with nixos-raspberrypi.nixosModules; [
                  raspberry-pi-4.base
                  raspberry-pi-4.display-vc4
                  raspberry-pi-4.bluetooth
                ];
              }
            )
            disko.nixosModules.disko
            ./hosts/kaitain
          ];
        };
      };
    };
}
