# OpenClaw VM - Ubuntu 24.04 with Node.js 24, NPM, and Nix
# Uses macvtap (direct mode) - VM gets IP on main network (192.168.1.x)
# SSH: ssh root@<VM_IP> or ssh muad@<VM_IP>
#
# Persistent config: OpenClaw config directory ~/.openclaw is symlinked to /mnt/share/openclaw
# This survives VM re-provisioning (overlay recreation).
#
# Disk management: Uses Nix store for immutable base image with QCOW2 overlay for mutable state
# - Base image: /nix/store/xxxx-ubuntu-noble-cloudimg/base.qcow2 (pinned, declarative)
# - Overlay: /mnt/arrakis/openclaw/disk/openclaw.qcow2 (created automatically on nixos-rebuild switch)
# - Update base: Change URL/hash in config, overlay auto-recreates
# - Reset to pristine: rm /mnt/arrakis/openclaw/disk/openclaw.qcow2 && systemctl restart libvirt-guest-openclaw
#
# NOTE: To get the correct sha256 hash for the base image, run:
#   nix-prefetch-url https://cloud-images.ubuntu.com/noble/20260108/noble-server-cloudimg-amd64.img
{
  config,
  lib,
  pkgs,
  ...
}:
let
  vmConfig = {
    name = "openclaw";
    vcpus = 4;
    memory = 6144; # MB - balloon handles dynamic allocation
    diskSize = "50G";
    dataPath = "/mnt/arrakis/openclaw";
  };

  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICPY19qVNxrSt4Ulb1C6L661wa6h0+GV+tX3HjsmUonl"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPaFk0BPHPq4TwAhBcs6fHhoztmpbO+IQrpvxn4xsMDO"
  ];

  # Declarative base image in Nix store (immutable)
  # Use nix-prefetch-url to get the sha256 hash for the URL below
  baseImage = pkgs.stdenv.mkDerivation {
    name = "ubuntu-noble-cloudimg";

    src = pkgs.fetchurl {
      url = "https://cloud-images.ubuntu.com/noble/20260108/noble-server-cloudimg-amd64.img";
      # Run: nix-prefetch-url https://cloud-images.ubuntu.com/noble/20260108/noble-server-cloudimg-amd64.img
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };

    nativeBuildInputs = [ pkgs.qemu ];
    dontUnpack = true;

    buildCommand = ''
      set -euo pipefail
      mkdir -p "$out"

      cp "$src" image.in
      ${pkgs.qemu}/bin/qemu-img convert -O qcow2 image.in temp.qcow2
      ${pkgs.qemu}/bin/qemu-img resize temp.qcow2 ${vmConfig.diskSize}
      install -m 0444 temp.qcow2 "$out/base.qcow2"
    '';
  };

  metaData = pkgs.writeText "meta-data" ''
    instance-id: ${vmConfig.name}
    local-hostname: ${vmConfig.name}
  '';

  userData = pkgs.writeText "user-data" ''
        #cloud-config
        users:
          - name: root
            shell: /bin/bash
            ssh_authorized_keys:
    ${lib.concatMapStrings (key: "          - ${key}\n") sshKeys}
          - name: muad
            shell: /bin/bash
            groups: [sudo]
            ssh_authorized_keys:
    ${lib.concatMapStrings (key: "          - ${key}\n") sshKeys}
          - name: calvo
            shell: /bin/bash
            sudo: ALL=(ALL) NOPASSWD:ALL
            groups: [sudo]
            ssh_authorized_keys:
    ${lib.concatMapStrings (key: "          - ${key}\n") sshKeys}
        bootcmd:
          - mkdir -p /mnt/share
        packages: [qemu-guest-agent, ca-certificates, curl, gnupg, nfs-common, build-essential, git]
        mounts:
          - [ "192.168.1.251:/mnt/arrakis/ix/openclaw/share", "/mnt/share", "nfs", "defaults,_netdev,nofail", "0", "0" ]
        runcmd:
          - DEBIAN_FRONTEND=noninteractive apt-get update
          - DEBIAN_FRONTEND=noninteractive apt-get upgrade -y -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold"
          - systemctl enable --now qemu-guest-agent || true
          - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
          - systemctl restart ssh
          - curl -fsSL https://deb.nodesource.com/setup_24.x | bash -
          - DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs
          - sudo -H -u muad bash -c 'mkdir -p $HOME/.npm-global && npm config set prefix $HOME/.npm-global && echo "export PATH=\$HOME/.npm-global/bin:\$PATH" >> $HOME/.bashrc'
          - sudo -H -u muad bash -c 'export PATH=$HOME/.npm-global/bin:$PATH && npm install -g openclaw || (echo "openclaw npm install failed (continuing)" >&2)'
          - curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
          # Create OpenClaw persistent config directory on NFS share
          - mkdir -p /mnt/share/openclaw
          # Ensure OpenClaw config is symlinked to persistent share for muad user
          - sudo -H -u muad bash -c 'if [ -e "$HOME/.openclaw" ] && [ ! -L "$HOME/.openclaw" ]; then mv "$HOME/.openclaw" "$HOME/.openclaw.backup.$(date +%s)"; fi'
          - sudo -H -u muad bash -c 'ln -sfn /mnt/share/openclaw "$HOME/.openclaw"'
  '';

  cloudInitIso =
    pkgs.runCommand "cloud-init.iso"
      {
        nativeBuildInputs = [ pkgs.cdrkit ];
      }
      ''
        mkdir -p cidata
        cp ${userData} cidata/user-data
        cp ${metaData} cidata/meta-data
        genisoimage -output $out -volid cidata -joliet -rock cidata/
      '';

  vmXmlFile = pkgs.writeText "${vmConfig.name}.xml" ''
    <domain type='kvm'>
      <name>${vmConfig.name}</name>
      <memory unit='MiB'>${toString vmConfig.memory}</memory>
      <vcpu placement='auto'>${toString vmConfig.vcpus}</vcpu>
      <os>
        <type arch='x86_64' machine='q35'>hvm</type>
        <boot dev='hd'/>
      </os>
      <features>
        <acpi/>
        <apic/>
      </features>
      <cpu mode='host-passthrough' check='none'/>
      <clock offset='utc'>
        <timer name='rtc' tickpolicy='catchup'/>
        <timer name='pit' tickpolicy='delay'/>
        <timer name='hpet' present='no'/>
      </clock>
      <on_poweroff>destroy</on_poweroff>
      <on_reboot>restart</on_reboot>
      <on_crash>destroy</on_crash>
      <devices>
        <emulator>${pkgs.qemu_kvm}/bin/qemu-system-x86_64</emulator>
        <disk type='file' device='disk'>
          <driver name='qemu' type='qcow2'/>
          <source file='${vmConfig.dataPath}/disk/${vmConfig.name}.qcow2'/>
          <target dev='vda' bus='virtio'/>
        </disk>
        <disk type='file' device='cdrom'>
          <driver name='qemu' type='raw'/>
          <source file='${vmConfig.dataPath}/cloud-init.iso'/>
          <target dev='sda' bus='sata'/>
          <readonly/>
        </disk>
        <interface type='direct'>
          <source dev='enp3s0' mode='bridge'/>
          <model type='virtio'/>
        </interface>
        <serial type='pty'>
          <target type='isa-serial' port='0'>
            <model name='isa-serial'/>
          </target>
        </serial>
        <console type='pty'>
          <target type='serial' port='0'/>
        </console>
        <channel type='unix'>
          <target type='virtio' name='org.qemu.guest_agent.0'/>
        </channel>
        <graphics type='vnc' port='-1' autoport='yes' listen='127.0.0.1'>
          <listen type='address' address='127.0.0.1'/>
        </graphics>
        <video>
          <model type='virtio' heads='1' primary='yes'/>
        </video>
        <memballoon model='virtio'>
          <stats period='10'/>
        </memballoon>
      </devices>
    </domain>
  '';
in
{
  homelab.libvirt.enable = true;

  systemd.tmpfiles.rules = [
    "d ${vmConfig.dataPath} 0755 root root -"
    "d ${vmConfig.dataPath}/disk 0755 root root -"
    "d ${vmConfig.dataPath}/share 0755 root root -"
    "L+ ${vmConfig.dataPath}/cloud-init.iso - - - - ${cloudInitIso}"
  ];

  systemd.services."libvirt-guest-${vmConfig.name}" = {
    description = "Libvirt guest: ${vmConfig.name}";
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RequiresMountsFor = [ vmConfig.dataPath ];
    };

    restartTriggers = [
      baseImage
      cloudInitIso
      vmXmlFile
    ];

    script = ''
      set -euo pipefail

      ${pkgs.coreutils}/bin/sleep 2

      disk_path="${vmConfig.dataPath}/disk/${vmConfig.name}.qcow2"
      base_path="${baseImage}/base.qcow2"
      lock_file="${vmConfig.dataPath}/disk/.${vmConfig.name}.lock"

      (
        ${pkgs.flock}/bin/flock -x 200

        # Query overlay's current backing file (inside lock)
        # -U: allow reading while VM may have image locked
        # Prefer full-backing-filename (absolute) over backing-filename (may be relative)
        current_backing="$(${pkgs.qemu}/bin/qemu-img info -U --output=json "$disk_path" 2>/dev/null \
          | ${pkgs.jq}/bin/jq -r '."full-backing-filename" // ."backing-filename" // empty' 2>/dev/null || true)"

        # Recreate overlay if missing or backing file changed
        if [ ! -f "$disk_path" ] || [ "$current_backing" != "$base_path" ]; then
          echo "Creating overlay: $disk_path -> $base_path"

          tmp="$(${pkgs.coreutils}/bin/mktemp -p "$(dirname "$disk_path")" ".${vmConfig.name}.qcow2.XXXXXX")"
          ${pkgs.qemu}/bin/qemu-img create -f qcow2 -b "$base_path" -F qcow2 "$tmp"
          chown libvirt-qemu:libvirt-qemu "$tmp"
          chmod 0640 "$tmp"
          mv -f "$tmp" "$disk_path"
        fi

      ) 200>"$lock_file"

      # XML definition tracking
      xml_hash_file="${vmConfig.dataPath}/.${vmConfig.name}.xml.sha256"
      new_hash=$(${pkgs.coreutils}/bin/sha256sum ${vmXmlFile} | ${pkgs.gawk}/bin/awk '{print $1}')
      old_hash=""
      if [ -f "$xml_hash_file" ]; then
        old_hash=$(${pkgs.coreutils}/bin/cat "$xml_hash_file")
      fi
      if [ "$new_hash" != "$old_hash" ]; then
        ${pkgs.libvirt}/bin/virsh define ${vmXmlFile}
        echo "$new_hash" > "$xml_hash_file"
      fi
      if ! ${pkgs.gnugrep}/bin/grep -q "^${vmConfig.name}$" <(${pkgs.libvirt}/bin/virsh list --name); then
        ${pkgs.libvirt}/bin/virsh start ${vmConfig.name}
      fi
    '';

    preStop = ''
      ${pkgs.libvirt}/bin/virsh shutdown ${vmConfig.name} || true
      for i in $(${pkgs.coreutils}/bin/seq 1 30); do
        if ! ${pkgs.gnugrep}/bin/grep -q "^${vmConfig.name}$" <(${pkgs.libvirt}/bin/virsh list --name); then
          exit 0
        fi
        ${pkgs.coreutils}/bin/sleep 1
      done
      ${pkgs.libvirt}/bin/virsh destroy ${vmConfig.name} || true
    '';
  };
}
