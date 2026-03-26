# User-specific desktop applications installed via Home Manager.
{ config, pkgs, inputs, username, ... }:

{
  home.packages = with pkgs; [
    brave
    kitty
    vscode
    bat
    throne
  ];
}
