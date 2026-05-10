{...}: {
  flake.nixosModules.firmware = {...}: {
    services.fwupd.enable = true;
  };
}