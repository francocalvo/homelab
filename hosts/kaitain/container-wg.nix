# Auto-generated using compose2nix v0.2.3.
{ pkgs, lib, ... }:

{
  # Containers
  virtualisation.oci-containers.containers."wg-easy" = {
    image = "ghcr.io/wg-easy/wg-easy:15";
    volumes = [
      # "/lib/modules:/lib/modules:ro"
      "/mnt/arrakis/wg:/etc/wireguard:rw"
    ];
    ports = [
      "51820:51820/udp"
      "51821:51821/tcp"
    ];
    log-driver = "journald";
    extraOptions = [
      "--cap-add=NET_ADMIN"
      "--cap-add=NET_RAW"
      "--cap-add=SYS_MODULE"
      "--ip6=fdcc:ad94:bacf:61a3::2a"
      "--ip=10.42.42.42"
      "--network-alias=wg-easy"
      "--network=kaitain_wg"
      "--sysctl=net.ipv4.conf.all.src_valid_mark=1"
      "--sysctl=net.ipv4.ip_forward=1"
      "--sysctl=net.ipv6.conf.all.disable_ipv6=0"
      "--sysctl=net.ipv6.conf.all.forwarding=1"
      "--sysctl=net.ipv6.conf.default.forwarding=1"
    ];
  };
  systemd.services."podman-wg-easy" = {
    serviceConfig = {
      Restart = lib.mkOverride 500 "always";
    };
    after = [
      "podman-network-kaitain_wg.service"
    ];
    requires = [
      "podman-network-kaitain_wg.service"
    ];
    partOf = [
      "podman-compose-kaitain-root.target"
    ];
    wantedBy = [
      "podman-compose-kaitain-root.target"
    ];
  };

  # Networks
  systemd.services."podman-network-kaitain_wg" = {
    path = [ pkgs.podman ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "podman network rm -f kaitain_wg";
    };
    script = ''
      podman network inspect kaitain_wg || podman network create kaitain_wg --driver=bridge --subnet=10.42.42.0/24 --subnet=fdcc:ad94:bacf:61a3::/64
    '';
    partOf = [ "podman-compose-kaitain-root.target" ];
    wantedBy = [ "podman-compose-kaitain-root.target" ];
  };

  # Ensure swag directory exists
  systemd.tmpfiles.rules = [
    "d /mnt/arrakis/wg 0755 1000 1000 -"
  ];
}
