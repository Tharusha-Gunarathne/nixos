# Git client configuration for user identity and defaults.
{ config, pkgs, inputs, username, ... }:

{
  programs.git = {
    enable = true;
    settings = {
      user = {
        name = "Tharush2002";
        email = "172119123+Tharusha-Gunarathne@users.noreply.github.com";
      };
    };
  };
}
