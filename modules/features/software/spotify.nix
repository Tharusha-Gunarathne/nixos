{ self, inputs, ... }: {
  flake.nixosModules.spotify = { config, pkgs, ... }:
  let
    username = config.myConfig.username;
    spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};
  in {
    home-manager.users.${username} = { config, lib, ... }: {
      imports = [ inputs.spicetify-nix.homeManagerModules.default ];

      programs.spicetify = {
        enable = true;

        spotifyPackage = pkgs.spotify.overrideAttrs (oldAttrs: {
          postInstall = (oldAttrs.postInstall or "") + ''
            wrapProgram $out/bin/spotify \
              --add-flags "--ozone-platform=x11"
          '';
        });

        enabledExtensions = with spicePkgs.extensions; [
          adblock
          hidePodcasts
          shuffle
          fullAppDisplay
        ];
        enabledCustomApps = with spicePkgs.apps; [
          marketplace
        ];
        theme = spicePkgs.themes.comfy;
        colorScheme = "Everforest";
      };

      home.activation.spicetifyColorInit = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${config.xdg.configHome}/spicetify/Themes/Comfy"
        if [ ! -f "${config.xdg.configHome}/spicetify/Themes/Comfy/color.ini" ]; then
          touch "${config.xdg.configHome}/spicetify/Themes/Comfy/color.ini"
        fi
      '';
    };
  };
}