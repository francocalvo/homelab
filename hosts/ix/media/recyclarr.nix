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
    # Size limits are MB per minute of runtime.
    # Sonarr 1080p caps prefer about 4.5 GB for a 45m episode and allow up to 9 GB.
    # Radarr 1080p caps prefer about 18 GB for a 2h movie and allow up to 36 GB.

    sonarr:
      series:
        base_url: http://sonarr:8989
        api_key: !secret sonarr_api_key
        delete_old_custom_formats: true
        quality_definition:
          type: series
          qualities:
            - name: HDTV-1080p
              max: 200
              preferred: 100

            - name: WEBRip-1080p
              max: 200
              preferred: 100

            - name: WEBDL-1080p
              max: 200
              preferred: 100

            - name: Bluray-1080p
              max: 200
              preferred: 100
        quality_profiles:
          - trash_id: 72dae194fc92bf828f32cde7744e51a1 # WEB-1080p
            reset_unmatched_scores:
              enabled: true

    radarr:
      movies:
        base_url: http://radarr:7878
        api_key: !secret radarr_api_key
        delete_old_custom_formats: true
        quality_definition:
          type: movie
          qualities:
            - name: Bluray-1080p
              max: 300
              preferred: 150

            - name: WEBDL-1080p
              max: 300
              preferred: 150

            - name: WEBRip-1080p
              max: 300
              preferred: 150
        quality_profiles:
          - trash_id: d1d67249d3890e49bc12e275d989a7e9 # HD Bluray + WEB
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
      "/run/secrets/recyclarr_secrets:/config/secrets.yml:ro"
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
