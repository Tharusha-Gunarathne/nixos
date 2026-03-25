# Home-level Niri configuration extension point
{ username, config, ... }:

let 
    here = toString ./.;
in 
{
    xdg.configFile."niri/config.kdl" = {
        source = config.lib.file.mkOutOfStoreSymlink
        "${here}/config.kdl";
    };
}
