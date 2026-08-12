# HomeLab

A multi-host homelab setup that is completely reproducible using NixOS.

## Architecture

- **Nix + NixOS**: System configuration and package management
- **Podman**: Container orchestration via OCI containers
- **Sops**: Encrypted secrets management with age keys

### Network topology

**The reverse proxy and the services live on two different boxes.** This trips
people (and agents) up, so to be explicit:

| Box | IP | Role |
| --- | --- | --- |
| `kaitain` | `192.168.0.100` | Reverse proxy only (SWAG/nginx, TLS termination on 443/80) |
| `ix` | `192.168.0.4` | Every actual service — containers listen on their own ports here |

Every `*.calvo.dev` name resolves to **kaitain** (`192.168.0.100`), which
terminates TLS and proxies back to **ix** (`192.168.0.4`) on the service's port.
The upstream address is hard-coded as `ixHost` in
`hosts/kaitain/container-swag.nix`.

Consequences worth knowing before you debug something:

- `https://<svc>.calvo.dev` goes through the proxy; `http://192.168.0.4:<port>`
  hits the service directly. Use the direct address to isolate whether a problem
  is the service or the proxy.
- A hostname will **not** answer on the service's own port —
  `litellm.calvo.dev:4000` is not a thing. The proxy listens on 443; only ix
  listens on 4000.
- The `networking.hosts` entries in `hosts/ix/default.nix` deliberately point
  `*.calvo.dev` at `192.168.0.100`, i.e. ix reaches its own services by looping
  out through the proxy. That is intentional, not a stale entry.
- Only `overleaf` currently has a Nix-generated proxy-conf. The rest live by hand
  in `/mnt/arrakis/swag` on kaitain (see the Roadmap item about Nginx config
  generators).

## Hosts

### ix (x86_64-linux) — `192.168.0.4`

Mini PC running media and cloud services:

- **Jellyfin**: Media streaming server
- **Nextcloud**: Personal cloud platform with Redis, PostgreSQL, and supporting
  services
- **Hermes Agent**: NousResearch Hermes Agent harness in a libvirt VM
- **LiteLLM**: OpenAI-compatible AI gateway on port 4000, backed by Postgres.
  Both its `config.yaml` and `.env` are sops secrets in `secrets/ix.yaml`
  (`litellm_config` / `litellm_env`), rendered to `/mnt/arrakis/litellm/`.
  Note `store_model_in_db: true` — models can also exist in Postgres without
  appearing in `config.yaml`, so check `GET /model/info` (not just
  `/v1/models`, which collapses duplicate `model_name`s) to see what is really
  registered.

### caladan (x86_64-linux)

Mini PC for local AI workflows. The initial configuration provides a hardened
SSH service, Tailscale connectivity, a Podman runtime, and the Hermes Agent CLI.
Hermes service configuration and provider credentials will be added separately.

### kaitain (aarch64-linux) — `192.168.0.100`

Raspberry Pi 4 running network services:

- **WireGuard Easy**: VPN server management
- **Speedtest Tracker**: Network performance monitoring
- **SWAG**: Secure Web Application Gateway (reverse proxy with SSL)

## Project Structure

```
.
├── flake.nix           # Main Nix flake configuration
├── hosts/              # Host-specific configurations
│   ├── ix/             # Mini PC configuration
│   ├── caladan/        # AI workflow Mini PC configuration
│   └── kaitain/        # Raspberry Pi configuration
├── lib/                # Custom library functions
├── modules/            # Reusable NixOS modules
├── secrets/            # Encrypted configuration files
└── .sops.yaml          # Secrets management configuration
```

## Usage

Build and deploy a specific host from within the host:

```bash
nixos-rebuild switch --flake .#<hostname>
```

### Initial Caladan installation

The bootstrap hardware configuration expects a UEFI system with an ext4 root
partition labeled `nixos` and a vfat EFI partition labeled `boot`. After
mounting both partitions below `/mnt`, generate the machine-specific hardware
configuration from the NixOS installer:

```bash
sudo nixos-generate-config --root /mnt
cp /mnt/etc/nixos/hardware-configuration.nix hosts/caladan/hardware-configuration.nix
sudo nixos-install --root /mnt --flake .#caladan
```

Commit the generated hardware configuration after the installation succeeds.

Authenticate Caladan with the tailnet after the first boot:

```bash
sudo tailscale up
tailscale status
```

Update flake inputs:

```bash
nix flake update
```

Build and deploy from current computer to a specific host:

```bash
nixos-rebuild switch --flake .#<hostname> --target-host <user>@<ip> --use-remote-sudo
```

Build and deploy from third computer computer to a specific host:

```bash
nixos-rebuild switch --flake .#<hostname> --target-host <user>@<ip> --build-host <buildname>@<buildip> --use-remote-sudo
```

## Roadmap

- [ ] Manage the Nginx config files using Nix generators.
- [ ] Deploy \*arr stack for media consumption.
- [ ] Create auto-backups of Postgres containers.
- [ ] Create auto-backups for Nextcloud webserver.
- [ ] Centralize logs management with ELK stack.
- [ ] Achieve rootless Podman deployments using Nix OCI containers.
