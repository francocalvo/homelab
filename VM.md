# VM Notes: Hermes (OpenClaw)

Hermes is the libvirt VM that runs the OpenClaw personal AI assistant gateway on
the `ix` host.

## Current status

- VM name: `hermes`
- Host: `ix` (NixOS)
- Config file: `hosts/ix/vm-hermes.nix`
- Network: libvirt macvtap/direct on `enp3s0`
- Disk path: `/mnt/arrakis/hermes/disk/hermes.qcow2`
- Cloud-init ISO: `/mnt/arrakis/hermes/cloud-init.iso`
- Systemd unit: `libvirt-guest-hermes.service`

## Disk management (QCOW2 overlay system)

The VM uses a declarative QCOW2 overlay system for reproducibility:

- **Base image**: stored in the Nix store as `ubuntu-noble-cloudimg/base.qcow2`
  (immutable, pinned URL/hash in the Nix config)
- **Overlay**: mutable QCOW2 at `/mnt/arrakis/hermes/disk/hermes.qcow2`
- **Automatic creation**: overlay is created atomically on base/ISO/XML changes
  via `restartTriggers`
- **Lock file**: `/mnt/arrakis/hermes/disk/.hermes.lock`

### Operations

| Task | Command |
|------|---------|
| Reset VM to pristine | `sudo rm -f /mnt/arrakis/hermes/disk/hermes.qcow2 && sudo systemctl restart libvirt-guest-hermes` |
| Update base image | Change URL/hash in `hosts/ix/vm-hermes.nix`, then `nixos-rebuild switch` |
| Check backing file | `qemu-img info /mnt/arrakis/hermes/disk/hermes.qcow2 \| grep backing` |
| Reclaim old base images | `nix-collect-garbage` after switching to a new base |

To get the hash for a new Ubuntu cloud image:

```bash
nix-prefetch-url https://cloud-images.ubuntu.com/noble/20260108/noble-server-cloudimg-amd64.img
```

## OpenClaw persistence

- The VM mounts the NAS export
  `192.168.0.251:/mnt/arrakis/ix/hermes/share` at `/mnt/share`.
- OpenClaw state is stored under `/mnt/share/openclaw`.
- The `muad` user's `~/.openclaw` is symlinked to `/mnt/share/openclaw` during
  cloud-init.
- The directory is owned by `muad:muad` after the NFS mount becomes available.

Useful checks inside the VM:

```bash
ls -la ~/.openclaw
ls -ld /mnt/share/openclaw
npm -g ls --depth=0
```

If OpenClaw gets `EACCES` errors writing to `~/.openclaw`, fix ownership:

```bash
sudo chown -R muad:muad /mnt/share/openclaw
```

## Fresh deployment from the old `openclaw` VM

This configuration intentionally creates a new Hermes VM and storage root. To
start from a clean OpenClaw context, remove the old VM and old OpenClaw storage
instead of migrating state:

```bash
sudo virsh shutdown openclaw || true
sudo virsh undefine openclaw || true
sudo rm -rf /mnt/arrakis/openclaw
sudo rm -rf /mnt/arrakis/hermes/share/openclaw
```

## Recovery plan

1. Destroy the VM without deleting the definition:
   ```bash
   sudo virsh destroy hermes || true
   ```
2. Delete the overlay:
   ```bash
   sudo rm -f /mnt/arrakis/hermes/disk/hermes.qcow2
   ```
3. Restart the service:
   ```bash
   sudo systemctl restart libvirt-guest-hermes
   ```
4. Find the IP from the router DHCP leases for hostname `hermes`, then SSH:
   ```bash
   ssh muad@<VM_IP>
   ```
5. Verify OpenClaw config persistence:
   ```bash
   ls -la ~/.openclaw
   ```

## Useful commands

- VM state: `sudo virsh domstate hermes`
- VM interfaces: `sudo virsh domiflist hermes`
- Disk/ISO attachments: `sudo virsh domblklist hermes`
- IP via agent: `sudo virsh domifaddr hermes --source agent`
- IP via ARP: `sudo virsh domifaddr hermes --source arp`

## Cloud-init summary

Cloud-init configures:

- Users: `root`, `muad`, and `calvo` with SSH keys
- Packages: `qemu-guest-agent`, `ca-certificates`, `curl`, `gnupg`,
  `nfs-common`, `build-essential`, and `git`
- NFS mount: `192.168.0.251:/mnt/arrakis/ix/hermes/share` -> `/mnt/share`
- SSH hardening and `qemu-guest-agent`
- Node.js 24 and global `openclaw` install for `muad`
- Determinate Nix installer
- OpenClaw persistence: `~/.openclaw` -> `/mnt/share/openclaw`
