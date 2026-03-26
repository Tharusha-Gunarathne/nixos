# System-wide packages installed for all users and root workflows.
{ config, lib, pkgs, username, ... }:

{
  environment.systemPackages = with pkgs; [
    vim
    git
    wget
    wl-clipboard
    brightnessctl
    tree
    vicinae
    xwayland-satellite
  ];
}
