# Bootloader and EFI settings for system startup.
{ config, lib, pkgs, username, ... }:

{
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
}
