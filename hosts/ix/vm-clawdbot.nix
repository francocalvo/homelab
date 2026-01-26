# clawdbot VM - Ubuntu 24.04 with Node.js/NPM and Nix
# Uses macvtap (direct mode) - VM gets IP on main network (192.168.1.x)
# SSH: ssh root@<VM_IP> or ssh muad@<VM_IP>
#
# Manual bootstrap (run once after deploying this config):
#   wget -O /mnt/arrakis/clawdbot/disk/clawdbot.qcow2 https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img
#   qemu-img resize /mnt/arrakis/clawdbot/disk/clawdbot.qcow2 50G
#   virsh start clawdbot
{
  config,
  lib,
  pkgs,
  ...
}:
let
  vmConfig = {
    name = "clawdbot";
    vcpus = 4;
    memory = 6144; # MB - balloon handles dynamic allocation
    diskSize = "50G";
    dataPath = "/mnt/arrakis/clawdbot";
  };

  sshKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICPY19qVNxrSt4Ulb1C6L661wa6h0+GV+tX3HjsmUonl"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIPaFk0BPHPq4TwAhBcs6fHhoztmpbO+IQrpvxn4xsMDO"
  ];

  metaData = pkgs.writeText "meta-data" ''
    instance-id: ${vmConfig.name}
    local-hostname: ${vmConfig.name}
  '';

  userData = pkgs.writeText "user-data" ''
    #cloud-config
    users:
      - name: root
        ssh_authorized_keys:
${lib.concatMapStrings (key: "          - ${key}\n") sshKeys}
      - name: muad
        ssh_authorized_keys:
${lib.concatMapStrings (key: "          - ${key}\n") sshKeys}
    packages: [qemu-guest-agent, ca-certificates, curl, gnupg, nfs-common]
    mounts:
      - [ "192.168.1.251:/mnt/arrakis/ix/clawdbot/share", "/mnt/share", "nfs", "defaults,_netdev", "0", "0" ]
    runcmd:
      - mkdir -p /mnt/share
      - systemctl enable --now qemu-guest-agent
      - sed -i 's/^#*PermitRootLogin.*/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config
      - systemctl restart ssh
      - curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
      - apt-get install -y nodejs
      - sudo -u muad bash -c 'mkdir -p ~/.npm-global && npm config set prefix ~/.npm-global && echo "export PATH=~/.npm-global/bin:$PATH" >> ~/.bashrc'
      - curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm
  '';

  cloudInitIso = pkgs.runCommand "cloud-init.iso" {
    nativeBuildInputs = [ pkgs.cdrkit ];
  } ''
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
    };

    script = ''
      sleep 2
      disk_path="${vmConfig.dataPath}/disk/${vmConfig.name}.qcow2"
      if [ ! -f "$disk_path" ]; then
        echo "Disk image missing: $disk_path" >&2
        exit 1
      fi
      current_bytes=$(${pkgs.qemu}/bin/qemu-img info --output=json "$disk_path" | ${pkgs.jq}/bin/jq -r '."virtual-size"')
      target_bytes=$(${pkgs.coreutils}/bin/numfmt --from=iec "${vmConfig.diskSize}")
      if [ "$current_bytes" -lt "$target_bytes" ]; then
        ${pkgs.qemu}/bin/qemu-img resize "$disk_path" "${vmConfig.diskSize}"
      elif [ "$current_bytes" -gt "$target_bytes" ]; then
        echo "Disk image larger than configured size (${vmConfig.diskSize}): $disk_path" >&2
        exit 1
      fi
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
      if ! ${pkgs.libvirt}/bin/virsh list --name | grep -q "^${vmConfig.name}$"; then
        ${pkgs.libvirt}/bin/virsh start ${vmConfig.name} || true
      fi
    '';

    preStop = ''
      ${pkgs.libvirt}/bin/virsh shutdown ${vmConfig.name} || true
      for i in $(seq 1 30); do
        if ! ${pkgs.libvirt}/bin/virsh list --name | grep -q "^${vmConfig.name}$"; then
          exit 0
        fi
        sleep 1
      done
      ${pkgs.libvirt}/bin/virsh destroy ${vmConfig.name} || true
    '';
  };
}
