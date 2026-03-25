# Hostname and NetworkManager configuration.
{ config, lib, pkgs, username, ... }:

{
  networking.hostName = "nixos";
  networking.networkmanager.enable = true;
}
