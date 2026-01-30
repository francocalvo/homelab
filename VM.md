# VM Notes: openclaw

## Current status
- VM name: `openclaw`
- Host: `ix` (NixOS)
- Libvirt VM using macvtap/direct on `enp3s0`
- Disk path: `/mnt/arrakis/openclaw/disk/openclaw.qcow2`
- Cloud-init ISO: `/mnt/arrakis/openclaw/cloud-init.iso`
- Current MAC: `52:54:00:3e:ed:7f`
- VM state: running (as of last check)

## Config file
- Nix file: `hosts/ix/vm-clawdbot.nix`
- Cloud-init is generated via Nix and linked into `/mnt/arrakis/openclaw/cloud-init.iso`
- `diskSize` is enforced: the service fails if missing, resizes up if smaller, errors if larger
- Libvirt XML is redefined only when the XML hash changes

## Recent actions
- Old VM definition removed: `virsh shutdown/destroy/undefine openclaw`
- Entire `/mnt/arrakis/openclaw` directory deleted
- Config pulled on `ix` and rebuild run; service failed because disk was missing (expected)
- Disk and ISO re-created; VM started

## Known issues
- `qemu-guest-agent` not responding yet; `virsh domifaddr --source agent` fails
- SSH to `muad@<vm-ip>` failing with `Permission denied (publickey)`
- Router shows a DHCP client named `ubuntu` (likely the VM)
- Host ARP scan does not show VM due to macvtap isolation


## Recovery plan (recommended)
1. Destroy the VM (not the definition):
   - `sudo virsh destroy openclaw || true`
2. Delete the qcow2:
   - `sudo rm -f /mnt/arrakis/openclaw/disk/openclaw.qcow2`
3. Re-download and resize the image:
   - `sudo wget -O /mnt/arrakis/openclaw/disk/openclaw.qcow2 https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img`
   - `sudo qemu-img resize /mnt/arrakis/openclaw/disk/openclaw.qcow2 50G`
4. Start the VM:
   - `sudo virsh start openclaw`
5. Find the IP:
   - Check router DHCP leases for MAC `52:54:00:3e:ed:7f` or hostname `openclaw`
6. SSH:
   - `ssh muad@<VM_IP>`
7. Mount NFS share (if not mounted):
   - `sudo mount /mnt/share`

## Useful commands
- VM state: `sudo virsh domstate openclaw`
- VM MAC: `sudo virsh domiflist openclaw`
- Disk/ISO attachments: `sudo virsh domblklist openclaw`
- IP via agent (if running): `sudo virsh domifaddr openclaw --source agent`
- IP via ARP (host might miss due to macvtap): `sudo virsh domifaddr openclaw --source arp`

## Notes
- Cloud-init includes:
  - Users: `root`, `muad`, `calvo` with SSH keys
  - bootcmd: creates `/mnt/share` directory early
  - Packages: `qemu-guest-agent`, `ca-certificates`, `curl`, `gnupg`, `nfs-common`, `build-essential`, `git`
  - Mount: NFS `192.168.1.251:/mnt/arrakis/ix/openclaw/share` -> `/mnt/share` (with nofail for robustness, auto-mounted)
  - runcmd: non-interactive apt operations, enable agent, SSH hardening, Node.js 24, Nix installer, `openclaw` npm install
- `openclaw` is installed globally for user `muad` in `~/.npm-global/bin/openclaw`
- If guest agent is not responding but SSH works, you can enable it inside the VM:
   - `sudo systemctl enable --now qemu-guest-agent`
- Verification: `npm -g ls --depth=0` or `npm -g bin` to check installed packages
