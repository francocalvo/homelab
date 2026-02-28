{
  pkgs,
  lib,
  config,
  ...
}:

/*
  Overleaf Deployment Runbook (manual ops reference)

  This module defines the Overleaf CE stack on `ix`:
  - `ix-overleaf` (sharelatex/sharelatex)
  - `ix-overleaf-mongo` (replica set: rs0)
  - `ix-overleaf-redis`

  1) Deploy this branch on ix
     - `cd ~/homelab`
     - `git switch feat/overleaf`
     - `git pull --ff-only`
     - `sudo nixos-rebuild switch --flake .#ix`

  2) Ensure reverse proxy route exists on kaitain (SWAG)
     File on kaitain:
     - `/mnt/arrakis/swag/nginx/proxy-confs/subdomains/overleaf.subdomain.conf`
     Expected upstream:
     - `192.168.1.4:8084`
     Then reload SWAG:
     - `sudo podman exec swag nginx -t`
     - `sudo podman restart swag`

  3) First login / launchpad
     - Open: `https://overleaf.calvo.dev/launchpad`
     If you get "Session error. Please check you have cookies enabled":
     - Make sure this container has:
       - `OVERLEAF_SECURE_COOKIE=true`
       - `OVERLEAF_BEHIND_PROXY=true`
       - `OVERLEAF_TRUSTED_PROXY_IPS=192.168.1.100,127.0.0.1,::1`
     - Clear site cookies and retry launchpad.

  4) TeX install strategy (inside container)
     Preferred (recommended): full TeX Live once, then rebuild all formats.
     - `sudo podman exec ix-overleaf sh -lc "tlmgr update --self"`
     - `sudo podman exec ix-overleaf sh -lc "tlmgr install scheme-full"`
     - `sudo podman exec ix-overleaf sh -lc "tlmgr path add"`
     - `sudo podman exec ix-overleaf sh -lc "fmtutil-sys --all"`
     Notes:
     - `scheme-full` is large and can take a long time.
     - This removes repeated "File `<pkg>.sty` not found" errors.

  5) If not using `scheme-full` (targeted installs)
     - `sudo podman exec ix-overleaf sh -lc "tlmgr install koma-script float subfiles babel-spanish pdfpages adjustbox wrapfig libertine apacite fontspec booktabs multirow enumitem pdflscape polyglossia biblatex"`
     Notes:
     - `bigstrut.sty` is provided by package `multirow`.
     - `fontspec` is needed when compiling with LuaLaTeX/XeLaTeX.

  6) Fix for LaTeX kernel/package mismatches
     Symptoms observed:
     - `\IfPDFManagementActiveF` undefined (from `pdflscape`)
     - `\tbl_save_outer_table_cols:` undefined (from `tabularx/array`)
     Cause:
     - Some packages updated while LaTeX kernel/tools formats stayed old.
     Fix (sync core + tools and rebuild formats):
     - `sudo podman exec ix-overleaf sh -lc "tlmgr update latex l3kernel latex-bin tools latex-lab firstaid babel graphics l3backend"`
     Verify format status (LuaLaTeX):
     - `sudo podman exec ix-overleaf sh -lc "lualatex --version | head -n 2"`

  7) If errors persist after installs/updates
     - Check project tree for uploaded local package files that override system TeX:
       `array.sty`, `tabularx.sty`, `pdflscape.sty`, `lscape.sty`, etc.
     - Remove local stale copies and compile again.

  8) Verify container health quickly
     - `sudo podman ps | grep ix-overleaf`
     - `sudo podman inspect ix-overleaf --format '{{json .Config.Env}}' | tr ',' '\n' | grep OVERLEAF_`
     - `sudo podman exec ix-overleaf sh -lc "tlmgr info --only-installed scheme-full | sed -n '1,20p'"`
     - `sudo podman exec ix-overleaf sh -lc "kpsewhich scrbook.cls biblatex.sty polyglossia.sty pdflscape.sty"`

  Important:
  - Any `tlmgr install/update` done this way is inside the running container.
  - These changes may be lost on container recreation unless baked into image/startup automation.
*/
let
  overleaf_version = "5.5.1";
in
{
  # Overleaf Web Application
  virtualisation.oci-containers.containers."ix-overleaf" = {
    image = "sharelatex/sharelatex:${overleaf_version}";
    environment = {
      "OVERLEAF_APP_NAME" = "Overleaf";
      "OVERLEAF_BEHIND_PROXY" = "true";
      "OVERLEAF_LISTEN_IP" = "0.0.0.0";
      "OVERLEAF_PORT" = "80";
      "OVERLEAF_TRUSTED_PROXY_IPS" = "192.168.1.100,127.0.0.1,::1";
      "OVERLEAF_SITE_URL" = "https://overleaf.calvo.dev";
      "OVERLEAF_MONGO_URL" = "mongodb://mongo/sharelatex";
      "OVERLEAF_REDIS_HOST" = "redis";
      # NOTE: OVERLEAF_SECURE_COOKIE is intentionally not set.
      # The git-bridge connects internally via http://sharelatex and needs
      # cookies without the Secure flag. SWAG still provides HTTPS to browsers.
    };
    volumes = [
      "/mnt/arrakis/overleaf/data:/var/lib/overleaf:rw"
      "/mnt/arrakis/overleaf/texlive:/usr/local/texlive:rw"
    ];
    ports = [ "8084:80/tcp" ];
    dependsOn = [
      "ix-overleaf-mongo"
      "ix-overleaf-redis"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=sharelatex"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-overleaf" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-ix_default.service"
      "overleaf-mongo-init-rs.service"
    ];
    requires = [
      "podman-network-ix_default.service"
      "overleaf-mongo-init-rs.service"
    ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  # MongoDB Backend
  virtualisation.oci-containers.containers."ix-overleaf-mongo" = {
    image = "mongo:6.0";
    cmd = [
      "--replSet"
      "rs0"
      "--bind_ip_all"
    ];
    volumes = [
      "/mnt/arrakis/overleaf/mongo:/data/db:rw"
      "/mnt/arrakis/overleaf/mongo_config:/data/configdb:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=mongo"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-overleaf-mongo" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [ "podman-network-ix_default.service" ];
    requires = [ "podman-network-ix_default.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  # Redis Backend
  virtualisation.oci-containers.containers."ix-overleaf-redis" = {
    image = "redis:6.2";
    cmd = [
      "--appendonly"
      "yes"
    ];
    volumes = [ "/mnt/arrakis/overleaf/redis:/data:rw" ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=redis"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-overleaf-redis" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [ "podman-network-ix_default.service" ];
    requires = [ "podman-network-ix_default.service" ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  # Overleaf needs MongoDB replica-set mode to support real-time updates.
  systemd.services.overleaf-mongo-init-rs = {
    description = "Initialize MongoDB replica set for Overleaf";
    after = [ "podman-ix-overleaf-mongo.service" ];
    requires = [ "podman-ix-overleaf-mongo.service" ];
    before = [ "podman-ix-overleaf.service" ];
    wantedBy = [ "podman-compose-ix-root.target" ];

    path = [
      pkgs.bash
      pkgs.coreutils
      pkgs.podman
    ];

    script = ''
      set -eu

      for i in $(seq 1 30); do
        if podman exec ix-overleaf-mongo mongosh --quiet --eval "db.adminCommand({ ping: 1 }).ok" | grep -q 1; then
          break
        fi
        sleep 2
      done

      podman exec ix-overleaf-mongo mongosh --quiet --eval '
        try {
          rs.status();
        } catch (err) {
          rs.initiate({
            _id: "rs0",
            members: [{ _id: 0, host: "mongo:27017" }]
          });
        }
      '
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  systemd.tmpfiles.rules = [
    "d /mnt/arrakis/overleaf 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/data 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/mongo 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/mongo_config 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/redis 0777 1000 1000 -"
    "d /mnt/arrakis/overleaf/texlive 0755 root root -"
  ];
}
