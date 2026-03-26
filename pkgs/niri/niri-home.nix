# Home-level Niri configuration extension point
{ lib, config, baseDir, ... }:

let 
    here = "${baseDir}/pkgs/niri";
in 
{
    # Niri Configuration 
    home.activation.niriConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${config.xdg.configHome}/niri"
        if [ ! -f "${config.xdg.configHome}/niri/config.kdl" ]; then
            cp ${here}/config.kdl ${config.xdg.configHome}/niri/config.kdl
        fi
        rm -f ${here}/config.kdl
        ln -sf "${config.xdg.configHome}/niri/config.kdl" ${here}/config.kdl
    '';

    # Noctalia Theme Configuration
    home.activation.noctaliaTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${config.xdg.configHome}/niri"
        if [ ! -f "${config.xdg.configHome}/niri/noctalia.kdl" ]; then
            cp ${here}/noctalia.kdl ${config.xdg.configHome}/niri/noctalia.kdl
        fi
        rm -f ${here}/noctalia.kdl
        ln -sf "${config.xdg.configHome}/niri/noctalia.kdl" ${here}/noctalia.kdl
    '';
}
