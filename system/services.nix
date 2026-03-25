# Power and battery-related background services.
{ config, lib, pkgs, username, ... }:

{
  # services.getty.autoLoginUser = "${username}";
  services.power-profiles-daemon.enable = true;
  services.upower.enable = true;
}
