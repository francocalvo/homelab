{
  pkgs,
  lib,
  ...
}:

let
  setupScript = pkgs.writeText "media-download-client-setup.py" ''
    import http.cookiejar
    import json
    import os
    import time
    import urllib.error
    import urllib.parse
    import urllib.request
    import xml.etree.ElementTree as ET


    QB_BASE = "http://127.0.0.1:8085"
    SONARR_BASE = "http://127.0.0.1:8989"
    RADARR_BASE = "http://127.0.0.1:7878"
    SECRET_FILE = os.environ.get("MEDIA_CLIENTS_SECRETS_FILE", "/run/secrets/media_clients_secrets")


    def read_simple_secret(path):
        values = {}
        with open(path, "r", encoding="utf-8") as handle:
            for raw_line in handle:
                line = raw_line.strip()
                if not line or line.startswith("#") or ":" not in line:
                    continue
                key, value = line.split(":", 1)
                values[key.strip()] = value.strip().strip("\"'")
        return values


    def wait_for(url, headers=None, attempts=60):
        last_error = None
        for _ in range(attempts):
            try:
                request = urllib.request.Request(url, headers=headers or {})
                with urllib.request.urlopen(request, timeout=5):
                    return
            except Exception as exc:
                last_error = exc
                time.sleep(2)
        raise RuntimeError(f"Timed out waiting for {url}: {last_error}")


    def arr_api_key(config_path):
        return ET.parse(config_path).getroot().findtext("ApiKey")


    def arr_request(base_url, api_key, method, path, payload=None):
        headers = {"X-Api-Key": api_key}
        data = None
        if payload is not None:
            data = json.dumps(payload).encode("utf-8")
            headers["Content-Type"] = "application/json"
        request = urllib.request.Request(
            f"{base_url}{path}",
            data=data,
            headers=headers,
            method=method,
        )
        with urllib.request.urlopen(request, timeout=30) as response:
            body = response.read()
        if not body:
            return None
        return json.loads(body.decode("utf-8"))


    def qb_login(username, password):
        cookie_jar = http.cookiejar.CookieJar()
        opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(cookie_jar))
        data = urllib.parse.urlencode({"username": username, "password": password}).encode("utf-8")
        request = urllib.request.Request(f"{QB_BASE}/api/v2/auth/login", data=data, method="POST")
        with opener.open(request, timeout=30) as response:
            body = response.read().decode("utf-8")
        if body.strip() != "Ok.":
            raise RuntimeError("qBittorrent login failed")
        return opener


    def qb_post(opener, path, form):
        data = urllib.parse.urlencode(form).encode("utf-8")
        request = urllib.request.Request(f"{QB_BASE}{path}", data=data, method="POST")
        with opener.open(request, timeout=30) as response:
            response.read()


    def configure_qbittorrent(username, password):
        opener = qb_login(username, password)
        qb_post(
            opener,
            "/api/v2/app/setPreferences",
            {
                "json": json.dumps(
                    {
                        "save_path": "/data/downloads",
                        "temp_path": "/data/downloads/incomplete",
                        "temp_path_enabled": True,
                    }
                )
            },
        )

        for category, save_path in {
            "tv-sonarr": "/data/downloads/tv-sonarr",
            "radarr": "/data/downloads/radarr",
        }.items():
            form = {"category": category, "savePath": save_path}
            try:
                qb_post(opener, "/api/v2/torrents/createCategory", form)
            except urllib.error.HTTPError as exc:
                if exc.code != 409:
                    raise
            qb_post(opener, "/api/v2/torrents/editCategory", form)


    def ensure_download_dirs():
        for path in [
            "/mnt/media/downloads",
            "/mnt/media/downloads/incomplete",
            "/mnt/media/downloads/tv-sonarr",
            "/mnt/media/downloads/radarr",
        ]:
            os.makedirs(path, exist_ok=True)
            try:
                os.chown(path, 1000, 1000)
            except PermissionError:
                print(f"warning: could not chown {path}; continuing")


    def ensure_root_folder(base_url, api_key, path):
        existing = arr_request(base_url, api_key, "GET", "/api/v3/rootfolder")
        if not any(item.get("path") == path for item in existing):
            arr_request(base_url, api_key, "POST", "/api/v3/rootfolder", {"path": path})


    def upsert_download_client(base_url, api_key, payload):
        existing = arr_request(base_url, api_key, "GET", "/api/v3/downloadclient")
        match = next(
            (
                item
                for item in existing
                if item.get("implementation") == "QBittorrent" or item.get("name") == payload["name"]
            ),
            None,
        )
        if match:
            payload = dict(payload)
            payload["id"] = match["id"]
            arr_request(base_url, api_key, "PUT", f"/api/v3/downloadclient/{match['id']}", payload)
        else:
            arr_request(base_url, api_key, "POST", "/api/v3/downloadclient", payload)


    def qb_client_payload(category_field, category):
        return {
            "enable": True,
            "protocol": "torrent",
            "priority": 1,
            "removeCompletedDownloads": True,
            "removeFailedDownloads": True,
            "name": "qBittorrent",
            "implementation": "QBittorrent",
            "configContract": "QBittorrentSettings",
            "tags": [],
            "fields": [
                {"name": "host", "value": "qbittorrent"},
                {"name": "port", "value": 8080},
                {"name": "useSsl", "value": False},
                {"name": "urlBase", "value": ""},
                {"name": "username", "value": SECRETS["qbittorrent_username"]},
                {"name": "password", "value": SECRETS["qbittorrent_password"]},
                {"name": category_field, "value": category},
                {"name": category_field.replace("Category", "ImportedCategory"), "value": ""},
                {"name": "recentTvPriority" if category_field == "tvCategory" else "recentMoviePriority", "value": 0},
                {"name": "olderTvPriority" if category_field == "tvCategory" else "olderMoviePriority", "value": 0},
                {"name": "initialState", "value": 0},
                {"name": "sequentialOrder", "value": False},
                {"name": "firstAndLast", "value": False},
                {"name": "contentLayout", "value": 0},
            ],
        }


    SECRETS = read_simple_secret(SECRET_FILE)
    for required in ["qbittorrent_username", "qbittorrent_password"]:
        if not SECRETS.get(required):
            raise RuntimeError(f"Missing required secret: {required}")

    ensure_download_dirs()
    wait_for(f"{QB_BASE}/api/v2/app/version")

    sonarr_key = arr_api_key("/home/muad/containers/media/sonarr/config.xml")
    radarr_key = arr_api_key("/home/muad/containers/media/radarr/config.xml")
    wait_for(f"{SONARR_BASE}/api/v3/system/status", {"X-Api-Key": sonarr_key})
    wait_for(f"{RADARR_BASE}/api/v3/system/status", {"X-Api-Key": radarr_key})

    configure_qbittorrent(SECRETS["qbittorrent_username"], SECRETS["qbittorrent_password"])
    ensure_root_folder(SONARR_BASE, sonarr_key, "/data/series")
    ensure_root_folder(RADARR_BASE, radarr_key, "/data/movies")
    upsert_download_client(SONARR_BASE, sonarr_key, qb_client_payload("tvCategory", "tv-sonarr"))
    upsert_download_client(RADARR_BASE, radarr_key, qb_client_payload("movieCategory", "radarr"))

    print("Configured qBittorrent, Sonarr, and Radarr download-client settings")
  '';
in
{
  systemd.services.media-download-client-setup = {
    description = "Configure qBittorrent download paths and Servarr download clients";
    after = [
      "podman-qbittorrent.service"
      "podman-sonarr.service"
      "podman-radarr.service"
    ];
    requires = [
      "podman-qbittorrent.service"
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
      export MEDIA_CLIENTS_SECRETS_FILE=/run/secrets/media_clients_secrets
      ${pkgs.python3}/bin/python3 ${setupScript}
    '';
  };
}
