# GTK theme, fonts, icons, cursor, and related dconf interface settings.
{ config, pkgs, inputs, ... }:

{
  # System-wide GTK theming packages
  # These affect ALL GTK apps for ALL users
  environment.systemPackages = with pkgs; [
    adwaita-icon-theme
    papirus-icon-theme
    gnome-themes-extra
  ];
}
