{...}: {
  flake.nixosModules.firmware = {pkgs, ...}: {
    services.fwupd.package = pkgs.fwupd;
    services.fwupd.enable = true;
  };
}