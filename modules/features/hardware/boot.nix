{...}: {
  flake.nixosModules.boot = {...}: {
    hardware.uinput.enable = true;
    boot.kernelModules = ["uinput"];
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;
  };
}
