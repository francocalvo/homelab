{ inputs, lib, pkgs, ... }:

with lib;
with lib.my;
{
  mkHost = path: attrs @ { system ? null, ... }:
    let
      # Ensure system is provided
      actualSystem = 
        if system == null 
        then throw "mkHost: system must be explicitly provided (e.g., system = \"x86_64-linux\")"
        else system;
      
      # Create system-specific pkgs
      systemPkgs = import inputs.nixpkgs {
        system = actualSystem;
        config.allowUnfree = true;
      };
    in
    nixosSystem {
      system = actualSystem;
      specialArgs = { 
        inherit lib inputs;
        system = actualSystem;
        pkgs = systemPkgs;
      };
      modules = [
        {
          nixpkgs.pkgs = systemPkgs;
          networking.hostName = mkDefault (removeSuffix ".nix" (baseNameOf path));
        }
        (filterAttrs (n: v: !elem n [ "system" ]) attrs)
        ../.   # /default.nix
        (import path)
      ];
    };

  mapHosts = dir: attrs @ { system ? system, ... }:
    mapModules dir
      (hostPath: mkHost hostPath attrs);
}
