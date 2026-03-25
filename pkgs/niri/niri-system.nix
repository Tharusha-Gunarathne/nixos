# Enable the Niri Wayland compositor at the system level.
{ config, lib, pkgs, username, ... }:

{
  programs.niri.enable = true;
}
