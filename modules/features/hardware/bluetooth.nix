{ self, ... }: {
  flake.nixosModules.bluetooth = { ... }: {
    hardware.bluetooth.enable = true;
    services.libinput.enable = true;
  };
}
