# Noctalia Home Manager module import and shell enablement.
{ config, pkgs, inputs, username, ... }:

let 
  here = toString ./.;
in 
{
  imports = [
    inputs.noctalia.noctalia-main.homeModules.default
    ./noctalia-plugins.nix
  ];

  programs.noctalia-shell = {
    enable = true;
  };

  # Noctalia Shell Settings configuration, with symlink to out-of-store settings file.
  xdg.configFile."noctalia/settings.json" = {
    source = config.lib.file.mkOutOfStoreSymlink 
      "${here}/settings.json";
  };

  # Noctalia plugin configuration, with symlink to out-of-store plugin config file.
  xdg.configFile."noctalia/plugins.json" = {
    source = config.lib.file.mkOutOfStoreSymlink
      "${here}/plugins.json";
  };
}
