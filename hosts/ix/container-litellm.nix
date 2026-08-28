# LiteLLM AI Gateway — unified API proxy for 100+ LLM providers
# Provides an OpenAI-compatible endpoint at port 4000.
#
# config.yaml is GENERATED from ./litellm/models.nix and mounted straight from the
# nix store. Only .env is still a sops secret (see secrets/ix.yaml):
#   litellm_env  → /mnt/arrakis/litellm/.env
#
# The model list was lifted out of the `litellm_config` secret on 2026-08-19 so
# that it is reviewable in git and can generate other artifacts (a public
# models.json manifest) from one definition. It holds no credentials — provider
# keys stay in litellm_env and are referenced as `os.environ/NAME` pointers, which
# LiteLLM resolves per request.
#
# Because the config is a store path, editing a model changes the volume spec,
# which changes the unit, which makes systemd recreate the container on
# `nixos-rebuild switch`. That is deliberate: the old sops-secret arrangement
# re-rendered the file in place without restarting anything, so config edits
# silently did not take effect until someone restarted the container by hand.
#
# The `chatgpt/*` models authenticate via an OAuth device-code flow instead of an
# API key. LiteLLM writes (and rewrites, on every token refresh) auth.json into
# $CHATGPT_TOKEN_DIR, so that path is a writable persistent bind mount — otherwise
# the one-time browser login has to be redone every container recreate.
#
# References:
#   https://docs.litellm.ai/docs/proxy/docker_quick_start
#   https://docs.litellm.ai/docs/providers/chatgpt
#   https://github.com/BerriAI/litellm
{
  pkgs,
  lib,
  config,
  ...
}:

let
  litellmConfig = import ./litellm/config.nix { inherit lib; };
  configFile = (pkgs.formats.yaml { }).generate "litellm-config.yaml" litellmConfig;

  # Public model manifest, generated from the same models.nix as configFile above.
  # Materialised at /etc/litellm/models.json (see environment.etc below) so it is
  # built and its models.nix sync assertion is checked on every rebuild, whatever
  # ends up serving it.
  manifestFile = pkgs.writeText "models.json" (
    builtins.toJSON (import ./litellm/manifest.nix { inherit lib; })
  );
in

{
  # Not consumed by the proxy — this is the harness-facing manifest, kept here so
  # a rebuild always regenerates and validates it alongside config.yaml.
  environment.etc."litellm/models.json".source = manifestFile;

  # Publish the manifest to https://litellm.calvo.dev/models.json.
  #
  # kaitain's SWAG serves /mnt/arrakis/swag/www, and that directory is only
  # reachable from kaitain: the TrueNAS box at 192.168.0.251 exports a per-host
  # subtree, so ix's /mnt/arrakis is /mnt/arrakis/ix and cannot see the swag
  # dataset. Hence a push rather than a shared path.
  #
  # rsync over ssh rather than an NFS mount of kaitain's export, even though that
  # export is world-mountable: it keeps the dependency one-directional and avoids
  # mounting the whole of another host's storage on ix to write one 15 KB file.
  #
  # restartTriggers means this only re-runs when the manifest content actually
  # changes, so an unrelated rebuild does not touch kaitain. A failure here (e.g.
  # kaitain down) is visible in `systemctl status litellm-manifest-publish` and
  # does NOT block activation of the rest of the system.
  systemd.services.litellm-manifest-publish = {
    description = "Publish the LiteLLM model manifest to kaitain's SWAG web root";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    restartTriggers = [ manifestFile ];
    path = [
      pkgs.rsync
      pkgs.openssh
    ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      rsync --checksum --times --chmod=F644 \
        -e 'ssh -o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new' \
        ${manifestFile} root@192.168.0.100:/mnt/arrakis/swag/www/models.json
    '';
  };

  systemd.services."podman-network-ix_litellm" = {
    path = [ pkgs.podman ];
    unitConfig.RequiresMountsFor = "/mnt/arrakis";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "${pkgs.podman}/bin/podman network rm -f ix_litellm";
    };
    script = ''
      podman network inspect ix_litellm || podman network create ix_litellm
    '';
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  ## DB Container
  virtualisation.oci-containers.containers."litellm-db" = {
    image = "postgres:17-alpine";
    environmentFiles = [ "/mnt/arrakis/litellm/.env" ];
    volumes = [ "/mnt/arrakis/litellm/database:/var/lib/postgresql/data" ];
    log-driver = "journald";
    extraOptions = [
      "--health-cmd=pg_isready -U litellm"
      "--health-interval=20s"
      "--health-timeout=3s"
      "--health-retries=5"
      "--network-alias=litellm-db"
      "--network=ix_litellm"
    ];
  };

  systemd.services."podman-litellm-db" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    unitConfig.RequiresMountsFor = "/mnt/arrakis";
    after = [ "podman-network-ix_litellm.service" ];
    requires = [ "podman-network-ix_litellm.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  ## LiteLLM Proxy Container
  virtualisation.oci-containers.containers."litellm" = {
    image = "ghcr.io/berriai/litellm:main-latest";
    environment = {
      # Set explicitly so token storage does not depend on the container's $HOME.
      CHATGPT_TOKEN_DIR = "/app/chatgpt-auth";
    };
    environmentFiles = [
      "/mnt/arrakis/litellm/.env"
    ];
    volumes = [
      # No `z` here, unlike the bind mounts below: that flag tells podman to
      # SELinux-relabel the source, which must never be done to a /nix/store path.
      # SELinux is not active on this host anyway, so it was already a no-op.
      "${configFile}:/app/config.yaml:ro"
      # rw + persistent: holds the ChatGPT OAuth auth.json across restarts.
      "/mnt/arrakis/litellm/chatgpt-auth:/app/chatgpt-auth:z"
    ];
    dependsOn = [
      "litellm-db"
    ];
    ports = [
      "4000:4000/tcp"
    ];
    log-driver = "journald";
    cmd = [
      "--config"
      "/app/config.yaml"
      "--detailed_debug"
    ];
    extraOptions = [
      "--network-alias=litellm"
      "--network=ix_litellm"
    ];
  };

  systemd.services."podman-litellm" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      # Create the ChatGPT token dir here rather than via tmpfiles: this unit
      # already orders itself after the /mnt/arrakis mount, so the directory
      # can never land on the bare mountpoint.
      ExecStartPre = [
        "${pkgs.coreutils}/bin/mkdir -p /mnt/arrakis/litellm/chatgpt-auth"
      ];
    };
    unitConfig.RequiresMountsFor = "/mnt/arrakis";
    after = [
      "podman-network-ix_litellm.service"
      "podman-litellm-db.service"
    ];
    requires = [
      "podman-network-ix_litellm.service"
    ];
    partOf = [
      "podman-compose-ix-root.target"
    ];
    wantedBy = [
      "podman-compose-ix-root.target"
    ];
  };
}
