{ inputs, lib, pkgs, ... }:

with lib;
with lib.my;
{
  mkHost = path: attrs @ { system ? null, ... }:
    let
      actualSystem = 
        if system == null 
        then throw "mkHost: system must be explicitly provided (e.g., system = \"x86_64-linux\")"
        else system;
    in
    nixosSystem {
      system = actualSystem;
      specialArgs = { 
        inherit lib inputs;
        system = actualSystem;
      };
      modules = [
        {
          networking.hostName = mkDefault (removeSuffix ".nix" (baseNameOf path));

          nixpkgs = {
            system = actualSystem;
            config.allowUnfree = true;
          };
        }

        inputs.sops-nix.nixosModules.sops

        (filterAttrs (n: v: !elem n [ "system" ]) attrs)
        ../.   # /default.nix
        (import path)
      ];
    };

  mapHosts = dir: attrs @ { system ? system, ... }:
    mapModules dir
      (hostPath: mkHost hostPath attrs);
}
