{...}: {
  flake.nixosModules.firmware = {pkgs, ...}: {
    services.fwupd.package = pkgs.fwupd;
    services.fwupd.enable = true;
    systemd.timers.fwupd-refresh.enable = false;
  };
}