# Home-level Niri configuration extension point
{ lib, config, baseDir, ... }:

{
    # Placeholder for Noctalia-Niri theming
    home.activation.noctaliaNiriConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
    mkdir -p "${config.xdg.configHome}/niri"
    if [ ! -f "${config.xdg.configHome}/niri/noctalia.kdl" ]; then
        touch "${config.xdg.configHome}/niri/noctalia.kdl"
    fi
    '';
    
    # Niri Configuration 
    xdg.configFile."niri/config.kdl".source = ./config.kdl;

}
