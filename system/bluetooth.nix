# Bluetooth and libinput device support.
{ config, lib, pkgs, username, ... }:

{
  hardware.bluetooth.enable = true;
  services.libinput.enable = true;
}
