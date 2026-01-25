# clawdbot VM - Ubuntu 24.04 with Node.js/NPM
# SSH: ssh -J muad@192.168.1.4 muad@$(virsh net-dhcp-leases default | awk '/clawdbot/{print $5}' | cut -d/ -f1)
#
# Manual bootstrap (run once on ix after deploying this config):
#
# 1. Download Ubuntu cloud image and resize disk:
#    wget -O /mnt/arrakis/clawdbot/disk/clawdbot.qcow2 https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
#    qemu-img resize /mnt/arrakis/clawdbot/disk/clawdbot.qcow2 50G
#
# 2. Create cloud-init meta-data:
#    cat > /mnt/arrakis/clawdbot/meta-data <<< $'instance-id: clawdbot\nlocal-hostname: clawdbot'
#
# 3. Create cloud-init user-data:
#    cat > /mnt/arrakis/clawdbot/user-data << 'EOF'
#    #cloud-config
#    users:
#      - name: muad
#        sudo: ALL=(ALL) NOPASSWD:ALL
#        ssh_authorized_keys:
#          - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICPY19qVNxrSt4Ulb1C6L661wa6h0+GV+tX3HjsmUonl
#          - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPaFk0BPHPq4TwAhBcs6fHhoztmpbO+IQrpvxn4xsMDO
#    packages: [qemu-guest-agent, nodejs, npm]
#    runcmd: [systemctl enable --now qemu-guest-agent]
#    EOF
#
# 4. Generate cloud-init ISO (requires cdrkit):
#    cd /mnt/arrakis/clawdbot && nix-shell -p cdrkit --run 'genisoimage -output cloud-init.iso -volid cidata -joliet -rock user-data meta-data'
#
# 5. Start libvirt default network (VM uses NAT, not bridge):
#    virsh net-start default && virsh net-autostart default
#
# 6. Start VM:
#    virsh start clawdbot
{
  config,
  lib,
  pkgs,
  ...
}:
let
  # Flexible resource configuration - adjust these values as needed
  vmConfig = {
    name = "clawdbot";
    vcpus = 2;
    memory = 4096; # MB
    diskSize = "50G";
    dataPath = "/mnt/arrakis/clawdbot";
    ubuntuVersion = "24.04";
  };

  # Libvirt XML domain definition
  vmXmlFile = pkgs.writeText "${vmConfig.name}.xml" ''
    <domain type='kvm'>
      <name>${vmConfig.name}</name>
      <memory unit='MiB'>${toString vmConfig.memory}</memory>
      <vcpu placement='static'>${toString vmConfig.vcpus}</vcpu>
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
        <interface type='bridge'>
          <source bridge='br0'/>
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
      </devices>
    </domain>
  '';
in
{
  homelab.libvirt.enable = true;

  # Ensure data directories exist
  systemd.tmpfiles.rules = [
    "d ${vmConfig.dataPath} 0755 root root -"
    "d ${vmConfig.dataPath}/disk 0755 root root -"
  ];

  # VM definition using libvirt XML
  systemd.services."libvirt-guest-${vmConfig.name}" = {
    description = "Libvirt guest: ${vmConfig.name}";
    after = [ "libvirtd.service" ];
    requires = [ "libvirtd.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };

    # Define and start VM
    script = ''
      # Wait for libvirtd to be fully ready
      sleep 2

      # Check if VM is already defined
      if ! ${pkgs.libvirt}/bin/virsh list --all --name | grep -q "^${vmConfig.name}$"; then
        ${pkgs.libvirt}/bin/virsh define ${vmXmlFile}
      fi

      # Start VM if not already running
      if ! ${pkgs.libvirt}/bin/virsh list --name | grep -q "^${vmConfig.name}$"; then
        ${pkgs.libvirt}/bin/virsh start ${vmConfig.name} || true
      fi
    '';

    preStop = ''
      ${pkgs.libvirt}/bin/virsh shutdown ${vmConfig.name} || true
      # Wait for graceful shutdown
      for i in $(seq 1 30); do
        if ! ${pkgs.libvirt}/bin/virsh list --name | grep -q "^${vmConfig.name}$"; then
          exit 0
        fi
        sleep 1
      done
      # Force destroy if graceful shutdown fails
      ${pkgs.libvirt}/bin/virsh destroy ${vmConfig.name} || true
    '';
  };
}
