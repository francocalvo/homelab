# VM Notes: openclaw

## Disk Management (QCOW2 Overlay System)

The VM now uses a declarative QCOW2 overlay system for better reproducibility:

- **Base image**: Stored in Nix store at `/nix/store/xxxx-ubuntu-noble-cloudimg/base.qcow2` (immutable, 0444 permissions)
- **Overlay**: Mutable QCOW2 at `/mnt/arrakis/openclaw/disk/openclaw.qcow2` (copy-on-write)
- **Automatic creation**: Overlay is created atomically on `nixos-rebuild switch`
- **Base image pinned**: URL and sha256 hash are in the Nix configuration
- **Lock file**: `/mnt/arrakis/openclaw/disk/.openclaw.lock` prevents concurrent creation

### Benefits

- Base image is declarative and tracked in config
- No manual disk download steps required
- Change hash → overlay recreates → clean reprovision
- Delete overlay manually → reset to pristine on next switch
- NFS persistence (already working) survives reprovisions
- **Hardening improvements**:
  - Atomic overlay creation prevents partial writes
  - Lock-based coordination prevents race conditions
  - VM can be running during rebuild (qemu-img -U)
  - Base image is explicitly read-only (0444 permissions)

### Operations

| Task | Command |
|------|---------|
| Reset VM to pristine | `rm /mnt/arrakis/openclaw/disk/openclaw.qcow2 && sudo systemctl restart libvirt-guest-openclaw` |
| Update base image | Change URL/hash in config, `nixos-rebuild switch` (overlay auto-recreates) |
| Check backing file | `qemu-img info /mnt/arrakis/openclaw/disk/openclaw.qcow2 \| grep backing` |
| Reclaim old base images | `nix-collect-garbage` (after switching to new base) |

### Migration from Old Setup

If you're migrating from the previous manual disk setup:

1. **Get the hash for the pinned image:**
   ```bash
   nix-prefetch-url https://cloud-images.ubuntu.com/noble/20260108/noble-server-cloudimg-amd64.img
   ```
   Update the `sha256` value in `hosts/ix/vm-clawdbot.nix`

2. **Stop the current VM:**
   ```bash
   sudo virsh shutdown openclaw
   ```

3. **Backup current state (optional):**
   ```bash
   cp /mnt/arrakis/openclaw/disk/openclaw.qcow2 /mnt/arrakis/openclaw/disk/openclaw.qcow2.backup
   ```

4. **Remove the old disk image:**
   ```bash
   rm /mnt/arrakis/openclaw/disk/openclaw.qcow2
   ```

5. **Deploy the new config:**
   ```bash
   sudo nixos-rebuild switch
   ```
   This will build the base image in the Nix store and create the overlay automatically.

6. **Verify:**
   ```bash
   qemu-img info /mnt/arrakis/openclaw/disk/openclaw.qcow2
   ```
   Should show `backing file: /nix/store/xxxx-ubuntu-noble-cloudimg/base.qcow2`

**Note**: A lock file at `/mnt/arrakis/openclaw/disk/.openclaw.lock` is used during overlay creation. If overlay creation is interrupted (e.g., crash), clean up any `.tmp` files in the disk directory and restart the service.

---

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
- **Disk management**: Uses Nix store base image with QCOW2 overlay (see "Disk Management" section above)
  - Base image is declarative (pinned URL + hash in Nix)
  - Overlay created automatically on `nixos-rebuild switch`
  - Overlay recreates if backing file changes (change hash in config)
- Libvirt XML is redefined only when the XML hash changes

## Config Persistence
- **OpenClaw config persistence**: The VM's `~/.openclaw` directory is symlinked to `/mnt/share/openclaw` (NFS)
- This ensures OpenClaw configuration survives VM re-provisioning (qcow2 replacement)
- The symlink is created automatically during cloud-init's `runcmd` phase
- **To reset OpenClaw config**: Delete the contents of `/mnt/share/openclaw` on the host (after stopping the VM)
- **To verify the symlink**: Inside the VM as user `muad`, run `ls -la ~/.openclaw` - it should point to `/mnt/share/openclaw`

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
    - `virsh destroy openclaw || true`
2. Delete the overlay:
    - `sudo rm -f /mnt/arrakis/openclaw/disk/openclaw.qcow2`
3. Restart the service (overlay auto-created from base image):
    - `sudo systemctl restart libvirt-guest-openclaw`
4. Find the IP:
    - Check router DHCP leases for MAC `52:54:00:3e:ed:7f` or hostname `openclaw`
5. SSH:
    - `ssh muad@<VM_IP>`
6. Mount NFS share (if not mounted):
    - `sudo mount /mnt/share`
7. Verify config persistence:
    - OpenClaw config should be automatically available via symlink `~/.openclaw` -> `/mnt/share/openclaw`
    - Configs survive this recovery process without manual intervention

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
   - **Config persistence**: Creates `/mnt/share/openclaw` and symlinks `~/.openclaw` -> `/mnt/share/openclaw` for user `muad`
- `openclaw` is installed globally for user `muad` in `~/.npm-global/bin/openclaw`
- OpenClaw configuration is stored persistently in `/mnt/share/openclaw` (NFS) via the symlink
- If guest agent is not responding but SSH works, you can enable it inside the VM:
   - `sudo systemctl enable --now qemu-guest-agent`
- Verification: `npm -g ls --depth=0` or `npm -g bin` to check installed packages
