{
  lib,
  ...
}:

let
  configDir = "/home/muad/containers/media/recyclarr";
in
{
  environment.etc."recyclarr/recyclarr.yml".text = ''
    # yaml-language-server: $schema=https://schemas.recyclarr.dev/v8/config-schema.json
    #
    # Default daily TRaSH Guides sync for Sonarr/Radarr.
    #
    # Recommended day-to-day profiles:
    # - Sonarr: WEB-1080p
    # - Radarr: HD Bluray + WEB
    #
    # 2160p and Remux profiles are synced too, but should be selected per
    # movie/show only when the playback device and network can direct-play them.

    sonarr:
      series:
        base_url: http://sonarr:8989
        api_key: !secret sonarr_api_key
        delete_old_custom_formats: true
        quality_definition:
          type: series
        quality_profiles:
          - trash_id: 72dae194fc92bf828f32cde7744e51a1 # WEB-1080p
            reset_unmatched_scores:
              enabled: true

          - trash_id: d1498e7d189fbe6c7110ceaabb7473e6 # WEB-2160p
            reset_unmatched_scores:
              enabled: true

    radarr:
      movies:
        base_url: http://radarr:7878
        api_key: !secret radarr_api_key
        delete_old_custom_formats: true
        quality_definition:
          type: movie
        quality_profiles:
          - trash_id: d1d67249d3890e49bc12e275d989a7e9 # HD Bluray + WEB
            reset_unmatched_scores:
              enabled: true

          - trash_id: 64fb5f9858489bdac2af690e27c8f42f # UHD Bluray + WEB
            reset_unmatched_scores:
              enabled: true

          - trash_id: 9ca12ea80aa55ef916e3751f4b874151 # Remux + WEB 1080p
            reset_unmatched_scores:
              enabled: true

          - trash_id: fd161a61e3ab826d3a22d53f935696dd # Remux + WEB 2160p
            reset_unmatched_scores:
              enabled: true
  '';

  virtualisation.oci-containers.containers."recyclarr" = {
    image = "ghcr.io/recyclarr/recyclarr:8";
    environment = {
      "CRON_SCHEDULE" = "0 5 * * *";
      "TZ" = "America/Argentina/Cordoba";
    };
    volumes = [
      "${configDir}:/config:rw"
      "/etc/recyclarr/recyclarr.yml:/config/recyclarr.yml:ro"
    ];
    log-driver = "journald";
    extraOptions = [
      "--user=1000:1000"
      "--network-alias=recyclarr"
      "--network=ix_default"
      "--security-opt=no-new-privileges"
    ];
  };

  systemd.services."podman-recyclarr" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-ix_default.service" ];
    requires = [ "podman-network-ix_default.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };
}
