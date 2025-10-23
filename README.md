# HomeLab

A multi-host homelab setup that is completely reproducible using NixOS.

## Architecture

- **Nix + NixOS**: System configuration and package management
- **Podman**: Container orchestration via OCI containers
- **Sops**: Encrypted secrets management with age keys

## Hosts

### ix (x86_64-linux)

Mini PC running media and cloud services:

- **Jellyfin**: Media streaming server
- **Nextcloud**: Personal cloud platform with Redis, PostgreSQL, and supporting
  services

### kaitain (aarch64-linux)

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
