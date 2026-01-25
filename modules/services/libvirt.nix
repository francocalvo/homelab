{ pkgs, lib, config, ... }:

with lib;

let
  cfg = config.homelab.libvirt;
in
{
  options.homelab.libvirt = {
    enable = mkEnableOption "libvirt virtualization";
  };

  config = mkIf cfg.enable {
    virtualisation.libvirtd = {
      enable = true;
      qemu = {
        package = pkgs.qemu_kvm;
        runAsRoot = true;
        swtpm.enable = true; # TPM emulation
      };
    };

    # Bridge networking for VMs
    networking.bridges.br0.interfaces = [ ]; # Host configures bridge

    # Allow users in libvirtd group to manage VMs
    users.users.muad.extraGroups = [ "libvirtd" ];

    environment.systemPackages = with pkgs; [
      virt-manager
      virt-viewer
    ];
  };
}
