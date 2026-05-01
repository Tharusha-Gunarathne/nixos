{...}: {
  flake.nixosModules.storage = {...}: {
    services.fstrim.enable = true;

    boot.kernelModules = ["kyber-iosched"];
    services.udev.extraRules = ''
      # set scheduler for NVMe
      ACTION=="add|change", KERNEL=="nvme[0-n]*", ATTR{queue/scheduler}="kyber"
      # set scheduler for SSD/HDD
      ACTION=="add|change", KERNEL=="sd[a-z]*|mmcblk[0-n]*", ATTR{queue/scheduler}="kyber"
    '';
  };
}
