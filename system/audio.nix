# PipeWire audio stack configuration.
{ config, lib, pkgs, username, ... }:

{
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };
}
