{
  pkgs,
  lib,
  ...
}:

let
  setupScript = pkgs.writeText "media-subtitle-setup.py" ''
    import json
    import time
    import urllib.error
    import urllib.parse
    import urllib.request
    import xml.etree.ElementTree as ET


    BAZARR_BASE = "http://127.0.0.1:6767"
    MANAGED_PROFILE_NAME = "English + Spanish"
    MANAGED_LANGUAGES = ["en", "es"]
    MANAGED_PROVIDERS = ["subtis", "subtitulamostv", "tvsubtitles", "yifysubtitles", "podnapisi"]


    def read_bazarr_api_key(path="/home/muad/containers/media/bazarr/config/config.yaml"):
        section = None
        with open(path, "r", encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if raw_line and not raw_line.startswith(" ") and line.endswith(":"):
                    section = line[:-1]
                    continue
                if section == "auth" and line.startswith("apikey:"):
                    return line.split(":", 1)[1].strip().strip("\"'")
        raise RuntimeError("Could not read Bazarr API key")


    def arr_api_key(config_path):
        return ET.parse(config_path).getroot().findtext("ApiKey")


    def request(method, path, api_key, form_items=None):
        headers = {"X-API-KEY": api_key}
        data = None
        if form_items is not None:
            data = urllib.parse.urlencode(form_items, doseq=True).encode("utf-8")
            headers["Content-Type"] = "application/x-www-form-urlencoded"

        req = urllib.request.Request(
            f"{BAZARR_BASE}/api/{path.lstrip('/')}",
            data=data,
            headers=headers,
            method=method,
        )
        with urllib.request.urlopen(req, timeout=30) as response:
            body = response.read()
        if not body:
            return None
        return json.loads(body.decode("utf-8"))


    def wait_for_bazarr(api_key, attempts=60):
        last_error = None
        for _ in range(attempts):
            try:
                request("GET", "system/status", api_key)
                return
            except Exception as exc:
                last_error = exc
                time.sleep(2)
        raise RuntimeError(f"Timed out waiting for Bazarr API: {last_error}")


    def managed_profile(profile_id):
        return {
            "profileId": profile_id,
            "name": MANAGED_PROFILE_NAME,
            "cutoff": None,
            "items": [
                {
                    "id": index,
                    "language": language,
                    "hi": "False",
                    "forced": "False",
                    "audio_exclude": "False",
                    "audio_only_include": "False",
                }
                for index, language in enumerate(MANAGED_LANGUAGES, start=1)
            ],
            "mustContain": [],
            "mustNotContain": [],
            "originalFormat": 0,
            "tag": None,
        }


    def upsert_profile(api_key):
        profiles = request("GET", "system/languages/profiles", api_key) or []
        existing = next((item for item in profiles if item.get("name") == MANAGED_PROFILE_NAME), None)
        if existing:
            profile_id = existing["profileId"]
        else:
            used_ids = {item.get("profileId") for item in profiles}
            profile_id = 1
            while profile_id in used_ids:
                profile_id += 1

        profiles = [item for item in profiles if item.get("profileId") != profile_id]
        profiles.append(managed_profile(profile_id))
        profiles.sort(key=lambda item: item["profileId"])
        return profile_id, profiles


    def current_enabled_languages(api_key):
        languages = request("GET", "system/languages", api_key) or []
        enabled = {item["code2"] for item in languages if item.get("enabled")}
        return sorted(enabled | set(MANAGED_LANGUAGES))


    def post_settings(api_key, sonarr_key, radarr_key):
        profile_id, profiles = upsert_profile(api_key)
        enabled_providers = request("GET", "system/settings", api_key)["general"].get("enabled_providers") or []
        enabled_providers = sorted(set(enabled_providers) | set(MANAGED_PROVIDERS))

        form = [
            ("languages-enabled", current_enabled_languages(api_key)),
            ("languages-profiles", json.dumps(profiles)),
            ("settings-general-enabled_providers", enabled_providers),
            ("settings-general-use_sonarr", "true"),
            ("settings-sonarr-ip", "sonarr"),
            ("settings-sonarr-port", "8989"),
            ("settings-sonarr-base_url", "/"),
            ("settings-sonarr-ssl", "false"),
            ("settings-sonarr-apikey", sonarr_key),
            ("settings-general-use_radarr", "true"),
            ("settings-radarr-ip", "radarr"),
            ("settings-radarr-port", "7878"),
            ("settings-radarr-base_url", "/"),
            ("settings-radarr-ssl", "false"),
            ("settings-radarr-apikey", radarr_key),
            ("settings-general-serie_default_enabled", "true"),
            ("settings-general-serie_default_profile", str(profile_id)),
            ("settings-general-movie_default_enabled", "true"),
            ("settings-general-movie_default_profile", str(profile_id)),
        ]
        request("POST", "system/settings", api_key, form)
        return profile_id


    def run_task(api_key, task_id):
        try:
            request("POST", "system/tasks", api_key, [("taskid", task_id)])
        except urllib.error.HTTPError as exc:
            if exc.code != 404:
                raise


    def assign_existing_series(api_key, profile_id):
        series = request("GET", "series?length=-1", api_key)
        items = (series or {}).get("data", [])
        if not items:
            return 0
        form = []
        for item in items:
            form.extend([
                ("seriesid", str(item["sonarrSeriesId"])),
                ("profileid", str(profile_id)),
            ])
        request("POST", "series", api_key, form)
        return len(items)


    def assign_existing_movies(api_key, profile_id):
        movies = request("GET", "movies?length=-1", api_key)
        items = (movies or {}).get("data", [])
        if not items:
            return 0
        form = []
        for item in items:
            form.extend([
                ("radarrid", str(item["radarrId"])),
                ("profileid", str(profile_id)),
            ])
        request("POST", "movies", api_key, form)
        return len(items)


    bazarr_key = read_bazarr_api_key()
    sonarr_key = arr_api_key("/home/muad/containers/media/sonarr/config.xml")
    radarr_key = arr_api_key("/home/muad/containers/media/radarr/config.xml")

    wait_for_bazarr(bazarr_key)
    profile_id = post_settings(bazarr_key, sonarr_key, radarr_key)
    time.sleep(2)
    run_task(bazarr_key, "update_series")
    run_task(bazarr_key, "update_movies")
    assigned_series = assign_existing_series(bazarr_key, profile_id)
    assigned_movies = assign_existing_movies(bazarr_key, profile_id)

    print(
        "Configured Bazarr subtitles: "
        f"profile_id={profile_id}, "
        f"providers={','.join(MANAGED_PROVIDERS)}, "
        f"assigned_series={assigned_series}, "
        f"assigned_movies={assigned_movies}"
    )
  '';
in
{
  virtualisation.oci-containers.containers."bazarr" = {
    image = "lscr.io/linuxserver/bazarr:latest";
    environment = {
      "PGID" = "1000";
      "PUID" = "1000";
      "TZ" = "America/Argentina/Cordoba";
    };
    volumes = [
      "/home/muad/containers/media/bazarr:/config:rw"
      "/mnt/media:/data:rw"
    ];
    ports = [
      "6767:6767/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=bazarr"
      "--network=ix_media"
    ];
  };

  systemd.services."podman-bazarr" = {
    serviceConfig.Restart = lib.mkOverride 90 "always";
    after = [ "podman-network-ix_media.service" ];
    requires = [ "podman-network-ix_media.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  systemd.services.media-subtitle-setup = {
    description = "Configure Bazarr subtitle providers and language profiles";
    after = [
      "podman-bazarr.service"
      "podman-sonarr.service"
      "podman-radarr.service"
    ];
    requires = [
      "podman-bazarr.service"
      "podman-sonarr.service"
      "podman-radarr.service"
    ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      ${pkgs.python3}/bin/python3 ${setupScript}
    '';
  };
}
