{
  pkgs,
  lib,
  config,
  ...
}:

let
  gitBridgeSrc = pkgs.fetchFromGitHub {
    owner = "valemir";
    repo = "overleaf-git-bridge-community";
    rev = "7341ef900988e88d89bec9d332430f3f56d819a5";
    hash = "sha256-dnfVJpG/9sqPpeOTqZnKbuh6h3BWRLEl1bflgHKHVfI=";
  };

  gitBridgeApp = pkgs.buildNpmPackage {
    pname = "overleaf-git-bridge-community";
    version = "0-unstable";
    src = gitBridgeSrc;
    npmDepsHash = "sha256-L3UihWO/m5TXxYsivQd7jxm0Jllfad0KseJAVf/9SrM=";
    dontNpmBuild = true;

    # Patches for Node 20 + Overleaf socket.io compatibility:
    # 1. The bundled xmlhttprequest treats "cookie" as a forbidden request header
    #    (per the browser spec) and silently drops it. The socket.io-client 0.9.x
    #    handshake needs to send the Overleaf session cookie.
    # 2. The websocket transport doesn't pass cookies in the WebSocket upgrade
    #    request. Overleaf's real-time service reads the session from the WS
    #    request cookies, so we inject them via ws headers option.
    postPatch = ''
      sed -i '/"cookie",/d; /"cookie2",/d' \
        lib/xmlhttprequest/lib/XMLHttpRequest.js

      sed -i 's|this.websocket = new Socket(this.prepareUrl() + query);|this.websocket = new Socket(this.prepareUrl() + query, { headers: { Cookie: this.socket.options.cookie \|\| "" } });|' \
        lib/socket.io-client/lib/transports/websocket.js
    '';

    installPhase = ''
      runHook preInstall
      mkdir -p $out/app
      cp -r . $out/app
      runHook postInstall
    '';
  };

  # The bundled socket.io-client 0.9.x expects a global `io` object that
  # existed in older Node versions. Node 20+ removed implicit `global`.
  nodePolyfill = pkgs.writeText "node-global-polyfill.js" ''
    if (typeof globalThis.global === 'undefined') {
      globalThis.global = globalThis;
    }
  '';

  entrypoint = pkgs.writeShellScript "entrypoint.sh" ''
    export PATH="${pkgs.coreutils}/bin:${pkgs.git}/bin:${pkgs.nodejs_20}/bin:$PATH"
    mkdir -p /root /var/olgitbridge /data /tmp
    git config --global user.email "gitbridge@overleaf"
    git config --global user.name "Git Bridge"
    exec node --require ${nodePolyfill} /app/src/server.js
  '';

  gitBridgeImage = pkgs.dockerTools.buildLayeredImage {
    name = "olgitbridge";
    tag = "local";
    contents = [
      gitBridgeApp
      pkgs.nodejs_20
      pkgs.git
      pkgs.cacert
      pkgs.bash
      pkgs.coreutils
      (pkgs.runCommand "git-usr-bin-symlink" {} ''
        mkdir -p $out/usr/bin
        ln -s ${pkgs.git}/bin/git $out/usr/bin/git
      '')
    ];
    config = {
      Entrypoint = [ "${entrypoint}" ];
      WorkingDir = "/app";
      ExposedPorts = {
        "5000/tcp" = {};
      };
    };
  };
in
{
  # Load the locally-built image into podman before starting the container
  systemd.services.podman-load-git-bridge = {
    description = "Load overleaf-git-bridge-community image into podman";
    after = [ "podman.service" ];
    requires = [ "podman.service" ];
    before = [ "podman-ix-git-bridge.service" ];
    wantedBy = [ "podman-compose-ix-root.target" ];

    path = [ pkgs.podman ];

    script = ''
      podman load --input ${gitBridgeImage}
    '';

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };

  # Git Bridge container
  virtualisation.oci-containers.containers."ix-git-bridge" = {
    image = "olgitbridge:local";
    environment = {
      "OVERLEAF_HOST" = "http://sharelatex";
      "NODE_EXTRA_CA_CERTS" = "/etc/ssl/certs/ca-bundle.crt";
    };
    volumes = [
      "/mnt/arrakis/overleaf/git-bridge/config.js:/app/config.js:ro"
      "/mnt/arrakis/overleaf/git-bridge/data:/data:rw"
    ];
    ports = [ "5000:5000/tcp" ];
    dependsOn = [ "ix-overleaf" ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=git-bridge"
      "--network=ix_default"
    ];
  };
  systemd.services."podman-ix-git-bridge" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
    };
    after = [
      "podman-network-ix_default.service"
      "podman-load-git-bridge.service"
      "podman-ix-overleaf.service"
    ];
    requires = [
      "podman-network-ix_default.service"
      "podman-load-git-bridge.service"
    ];
    partOf = [ "podman-compose-ix-root.target" ];
    wantedBy = [ "podman-compose-ix-root.target" ];
  };

  systemd.tmpfiles.rules = [
    "d /mnt/arrakis/overleaf/git-bridge 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/git-bridge/data 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/git-bridge/data/blues 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/git-bridge/data/hashes 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/git-bridge/data/pads 0755 1000 1000 -"
    "d /mnt/arrakis/overleaf/git-bridge/data/repos 0755 1000 1000 -"
  ];
}
