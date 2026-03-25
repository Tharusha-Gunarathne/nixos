# System-wide font packages.
{ config, lib, pkgs, username, ... }:

{
  fonts.packages = with pkgs; [
    nerd-fonts.jetbrains-mono
    ubuntu-sans
  ];
}
