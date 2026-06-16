# LiteLLM AI Gateway — unified API proxy for 100+ LLM providers
# Provides an OpenAI-compatible endpoint at port 4000.
#
# Both config.yaml and .env are managed as sops secrets (see secrets/ix.yaml):
#   litellm_config  → /mnt/arrakis/litellm/config.yaml
#   litellm_env     → /mnt/arrakis/litellm/.env
#
# References:
#   https://docs.litellm.ai/docs/proxy/docker_quick_start
#   https://github.com/BerriAI/litellm
{
  pkgs,
  lib,
  config,
  ...
}:

{
  virtualisation.oci-containers.containers."litellm" = {
    image = "ghcr.io/berriai/litellm:main-latest";
    environmentFiles = [
      "/mnt/arrakis/litellm/.env"
    ];
    volumes = [
      "/mnt/arrakis/litellm/config.yaml:/app/config.yaml:ro,z"
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
      "--network=ix_default"
    ];
  };

  systemd.services."podman-litellm" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    unitConfig.RequiresMountsFor = "/mnt/arrakis";
    after = [
      "podman-network-ix_default.service"
    ];
    requires = [
      "podman-network-ix_default.service"
    ];
    partOf = [
      "podman-compose-ix-root.target"
    ];
    wantedBy = [
      "podman-compose-ix-root.target"
    ];
  };
}
