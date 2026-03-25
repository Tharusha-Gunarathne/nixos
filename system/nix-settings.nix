# Nix daemon settings, unfree policy, and system state version.
{ config, lib, pkgs, username, ... }:

{
  nixpkgs.config.allowUnfree = true;
  nix.settings.experimental-features = [ "nix-command" "flakes" ];
  system.stateVersion = "25.11";
}
