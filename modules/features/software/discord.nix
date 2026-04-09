{...}: {
  flake.nixosModules.discord = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.username;

    noctaliaThemeCss = pkgs.writeText "noctalia.theme.css" ''
      /**
       * @name Noctalia
       * @description Noctalia color scheme theme for Discord
       * @author Noctalia
       */
      /* Colors will be populated by Noctalia on first color scheme change */
    '';

    noctaliaMaterialThemeCss = pkgs.writeText "noctalia-material.theme.css" ''
      /**
       * @name Noctalia Material
       * @description Noctalia material color scheme theme for Discord
       * @author Noctalia
       */
      /* Colors will be populated by Noctalia on first color scheme change */
    '';
  in {
    home-manager.users.${username} = {
      lib,
      pkgs,
      ...
    }: {
      home.packages = [pkgs.vesktop];

      home.activation.vesktopThemesDir = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "$HOME/.config/vesktop/themes"

        if [ ! -f "$HOME/.config/vesktop/themes/noctalia.theme.css" ]; then
          ${pkgs.coreutils}/bin/install -m 644 ${noctaliaThemeCss} \
            "$HOME/.config/vesktop/themes/noctalia.theme.css"
        fi

        if [ ! -f "$HOME/.config/vesktop/themes/noctalia-material.theme.css" ]; then
          ${pkgs.coreutils}/bin/install -m 644 ${noctaliaMaterialThemeCss} \
            "$HOME/.config/vesktop/themes/noctalia-material.theme.css"
        fi
      '';
    };
  };
}