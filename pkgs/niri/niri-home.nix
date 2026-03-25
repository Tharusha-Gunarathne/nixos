# Home-level Niri configuration extension point
{ username, config, ... }:

let 
    here = toString ./.;
in 
{
    # Niri Confiuration 
    home.activation.niriConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${config.xdg.configHome}/niri"
        if [ ! -f "${config.xdg.configHome}/niri/config.kdl" ]; then
            cp ${here}/niri/config.kdl ${config.xdg.configHome}/niri/config.kdl
        fi
        rm -f ${here}/niri/config.kdl
        ln -sf "${config.xdg.configHome}/niri/config.kdl" ${here}/niri/config.kdl
    '';

    # Noctalia Theme Configuration
    home.activation.noctaliaTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${config.xdg.configHome}/noctalia"
        if [ ! -f "${config.xdg.configHome}/noctalia/theme.json" ]; then
            cp ${here}/noctalia/theme.json ${config.xdg.configHome}/noctalia/theme.json
        fi
        rm -f ${here}/noctalia/theme.json
        ln -sf "${config.xdg.configHome}/noctalia/theme.json" ${here}/noctalia/theme.json
    '';
}
