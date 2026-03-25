# noctalia-plugins.nix
{ inputs, ... }:

let
  # Direct access to the grouped plugins from your registry
  pluginSet = inputs.noctalia.plugins;
in
{
  xdg.configFile = builtins.listToAttrs (map (name: {
    name = "noctalia/plugins/${name}";
    value = { source = pluginSet.${name}; };
  }) (builtins.attrNames pluginSet));
}
