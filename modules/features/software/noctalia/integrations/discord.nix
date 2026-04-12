{...}: {
  flake.nixosModules.noctaliaDiscord = {
    config,
    lib,
    pkgs,
    ...
  }: let
    username = config.myConfig.username;
    shell = config.myConfig.shell;
  in {
    config = lib.mkIf (shell == "noctalia") {
      home-manager.users.${username} = {
        lib,
        pkgs,
        ...
      }: {
        home.activation.noctaliaDiscordSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
          VENCORD_SETTINGS="$HOME/.config/vesktop/settings/settings.json"

          rm -f "$VENCORD_SETTINGS.backup"

          if [ -L "$VENCORD_SETTINGS" ]; then
            STORE_VENCORD=$(readlink "$VENCORD_SETTINGS")
            rm "$VENCORD_SETTINGS"
            ${pkgs.coreutils}/bin/install -m 644 "$STORE_VENCORD" "$VENCORD_SETTINGS"
          fi

          if [ ! -e "$HOME/.config/vesktop/themes/noctalia.theme.css" ]; then
            ${pkgs.coreutils}/bin/install -m 644 /dev/null \
              "$HOME/.config/vesktop/themes/noctalia.theme.css"
          fi

          if [ ! -e "$HOME/.config/vesktop/themes/noctalia-material.theme.css" ]; then
            ${pkgs.coreutils}/bin/install -m 644 /dev/null \
              "$HOME/.config/vesktop/themes/noctalia-material.theme.css"
          fi
        '';
      };
    };
  };
}