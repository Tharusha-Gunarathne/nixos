# System module aggregator importing all machine-wide NixOS modules.
{ config, lib, pkgs, username, ... }:

{
  imports = [
    ../hardware/hardware-configuration.nix
    ./boot.nix
    ./network.nix
    ./locale.nix
    ./nvidia.nix
    ./audio.nix
    ./bluetooth.nix
    ./display-manager.nix
    ./services.nix
    ./users.nix
    ./fonts.nix
    ./packages.nix
    ./nix-settings.nix
    ../pkgs/nautilus/nautilus-system.nix
    ../pkgs/niri/niri-system.nix
    ../pkgs/gtk/gtk-system.nix
  ];
}
