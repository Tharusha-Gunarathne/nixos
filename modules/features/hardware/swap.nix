{...}: {
  flake.nixosModules.swap = {...}: {
    swapDevices = [
      {
        device = "/var/lib/swapfile";
        size = 5 * 1024; # 5GB in MB
      }
    ];
  };
}
