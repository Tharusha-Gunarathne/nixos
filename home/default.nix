# Home Manager module aggregator plus home identity and state version.
{ config, pkgs, inputs, username, baseDir, ... }:

{
  imports = [
    ./packages.nix
    ./variables.nix
    ../pkgs/git/git.nix
    ../pkgs/nautilus/nautilus-home.nix
    ../pkgs/noctalia/noctalia.nix
    ../pkgs/kitty/kitty.nix
    ../pkgs/niri/niri-home.nix  
    ../pkgs/gtk/gtk-home.nix
    ../pkgs/vicinae/vicinae.nix
    ../pkgs/neovim/neovim.nix
  ];

  home.username = username;
  home.homeDirectory = "/home/${username}";
  home.stateVersion = "25.11";
}
