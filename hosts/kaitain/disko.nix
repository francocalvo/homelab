{ config, lib, ... }:

{
  disko.devices.disk.main = {
    type = "disk";
    device = "/dev/sda";

    content = {
      type = "gpt";
      partitions = {

        FIRMWARE = {
          label = "FIRMWARE";
          priority = 1;
          type = "0700"; # Microsoft basic data
          attributes = [ 0 ]; # Required Partition
          size = "1024M";
          content = {
            type = "filesystem";
            format = "vfat";
            mountpoint = "/boot/firmware";
            mountOptions = [
              "noatime"
              "noauto"
              "x-systemd.automount"
              "x-systemd.idle-timeout=1min"
            ];
          };
        };


        system = {
          label = "NIXOS_SD";
          type = "8300"; # Linux filesystem
          size = "100G"; # Leave space for swap
          content = {
            type = "filesystem";
            format = "ext4";
            mountpoint = "/";
            mountOptions = [ "noatime" ];
          };
        };
      };
    };
  };
}

