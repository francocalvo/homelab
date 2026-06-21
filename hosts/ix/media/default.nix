{
  ...
}:

{
  imports = [
    ./prowlarr.nix
    ./sonarr.nix
    ./radarr.nix
    ./qbittorrent.nix
    ./bazarr.nix
    ./recyclarr.nix
    ./flaresolverr.nix
    ./download-clients.nix
    ./seerr.nix
  ];

  systemd.tmpfiles.rules = [
    "d /home/muad/containers/media 0755 1000 1000 -"
    "d /home/muad/containers/media/prowlarr 0755 1000 1000 -"
    "d /home/muad/containers/media/sonarr 0755 1000 1000 -"
    "d /home/muad/containers/media/radarr 0755 1000 1000 -"
    "d /home/muad/containers/media/qbittorrent 0755 1000 1000 -"
    "d /home/muad/containers/media/bazarr 0755 1000 1000 -"
    "d /home/muad/containers/media/recyclarr 0755 1000 1000 -"
    "d /home/muad/containers/media/seerr 0755 1000 1000 -"
  ];
}
