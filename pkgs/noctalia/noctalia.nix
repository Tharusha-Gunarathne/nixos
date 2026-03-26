# Noctalia Home Manager module import and shell enablement.
{ config, pkgs, inputs, lib, baseDir, ... }:

let 
  here = "${baseDir}/pkgs/noctalia";
in 
{
  imports = [
    inputs.noctalia.noctalia-main.homeModules.default
    ./noctalia-sync.nix
    ./noctalia-plugins.nix
  ];

  programs.noctalia-shell = {
    enable = true;
  };

  # Noctalia Shell Settings configuration, with symlink to out-of-store settings file.
  home.activation.noctaliaSettings = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "${config.xdg.configHome}/noctalia"
    if [ ! -f "${config.xdg.configHome}/noctalia/settings.json" ]; then
      cp ${here}/settings.json ${config.xdg.configHome}/noctalia/settings.json
    fi
  '';

  # Noctalia plugin configuration, with symlink to out-of-store plugin config file.
  home.activation.noctaliaPlugins = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "${config.xdg.configHome}/noctalia"
    if [ ! -f "${config.xdg.configHome}/noctalia/plugins.json" ]; then
      cp ${here}/plugins.json ${config.xdg.configHome}/noctalia/plugins.json
    fi
  '';
}
