# Application-only cache targets. This reads the public lockfile, not .env.local
# or the NixOS configuration. Use only with a cache you are licensed to populate.
{system ? "x86_64-linux"}: let
  lock = builtins.fromJSON (builtins.readFile ../flake.lock);
  source = builtins.fetchTree lock.nodes.${lock.nodes.root.inputs.nixpkgs}.locked;
  pkgs = import source.outPath {
    inherit system;
    config.allowUnfree = true;
  };
in {
  jetbrains-idea = pkgs.jetbrains.idea;
  jetbrains-pycharm = pkgs.jetbrains.pycharm;
  jetbrains-webstorm = pkgs.jetbrains.webstorm;
  jetbrains-phpstorm = pkgs.jetbrains.phpstorm;
  jetbrains-datagrip = pkgs.jetbrains.datagrip;
  jetbrains-rust-rover = pkgs.jetbrains.rust-rover;
  vesktop = pkgs.vesktop;
  brave = pkgs.brave;
  microsoft-edge = pkgs.microsoft-edge;
  vscode = pkgs.vscode;
  lmstudio = pkgs.lmstudio;
  postman = pkgs.postman;
  spotify = pkgs.spotify;
  antigravity = pkgs.antigravity-ide;
}
