{ self, inputs, ... }: {
  flake.nixosModules.spotify = { config, pkgs, lib, ... }:
  let
    username = config.myConfig.username;
    spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  in {
    imports = [ inputs.spicetify-nix.nixosModules.default ];

    programs.spicetify = {
      enable = true;
      enabledExtensions = with spicePkgs.extensions; [
        adblock
        hidePodcasts
        shuffle
      ];
      theme = spicePkgs.themes.catppuccin;
      colorScheme = "mocha";
    };
  };
}