{...}: {
  flake.nixosModules.fastfetch = {
    config,
    lib,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
  in {
    home-manager.users.${username} = {pkgs, ...}: {
      programs.fastfetch.enable = true;

      xdg.configFile."fastfetch/config.jsonc".source = ./config.jsonc;
    };
  };
}