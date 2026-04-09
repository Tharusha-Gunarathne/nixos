{...}: {
  flake.nixosModules.swap = {...}: {
    swapDevices = [
      {
        device = "/var/lib/swapfile";
        size = 25 * 1024; # 25GB in MB
      }
    ];
  };
}
