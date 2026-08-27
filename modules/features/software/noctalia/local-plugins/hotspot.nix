#
# Declarative install of the Noctalia hotspot plugin.
#
# One file per locally authored plugin lives in this directory
# (modules/features/software/noctalia/local-plugins/), each producing its own
# flake.nixosModules.<name> and imported automatically via import-tree --
# nothing extra to wire up. This keeps
# modules/features/software/noctalia/ itself down to plugins.nix (community
# plugins) and this directory (yours), instead of accumulating one
# *Plugin.nix per plugin at that level.
#
# The plugin source lives in its own repo
# (github:tharusha-gunarathne/noctalia-hotspot) and is pinned as a
# `flake = false` input -- but deliberately NOT in the root flake.nix.
# It's declared inside plugins/noctalia/flake.nix instead, which already
# re-exports its own inputs (`outputs = {...} @ inputs: { inherit inputs; };`),
# so it's reached here as inputs.noctalia.inputs.noctalia-hotspot-plugin
# rather than as a top-level input of its own. `flake = false` means it's a
# plain source fetch with no nixpkgs and no lock of its own, so nesting it
# here carries none of the follows/hash-divergence risk documented for
# nested *flake* inputs.
#
# To add or update it:
#   edit plugins/noctalia/flake.nix, then from ~/nixos:
#     nix flake lock --update-input noctalia
#
# Iterate on a local checkout without editing the wrapper flake at all.
# `--override-input` takes a slash-separated path for transitive inputs:
#   sudo nixos-rebuild switch --flake 'path:.#nixos' \
#     --override-input noctalia/noctalia-hotspot-plugin \
#     path:REDACTED-HOME/dev/noctalia-hotspot
#
# Noctalia treats ~/.local/share/noctalia/plugins/<dir>/ as a built-in "local"
# source and scans it on startup, so nothing has to be registered in
# config.toml and no directory has to be created by hand. The plugin then
# appears in Settings -> Plugins with an enable toggle like any other.
#
# `recursive = true` matters: it symlinks each file individually into a real
# directory, rather than making the whole plugin directory one symlink into
# the store. Noctalia's scanner is happier with the former, and the plugin
# directory stays read-only either way -- which is fine, because plugin
# settings persist to the state dir, not next to the code.
#
{
  inputs,
  localConfig,
  ...
}: {
  flake.nixosModules.noctaliaHotspotPlugin = {...}: let
    hotspotUser = localConfig.user.username;
    hotspotPluginSrc = inputs.noctalia.inputs.noctalia-hotspot-plugin;
  in {
    home-manager.users.${hotspotUser}.home.file.".local/share/noctalia/plugins/hotspot" = {
      source = "${hotspotPluginSrc}/hotspot";
      recursive = true;
    };
  };
}
