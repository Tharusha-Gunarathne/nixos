{inputs, ...}: {
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

    vesktopSettingsFallback = pkgs.writeText "vesktop-settings.json" (builtins.toJSON {
      discordBranch = "stable";
      minimizeToTray = false;
      arRPC = true;
      splashColor = "rgb(196, 198, 208)";
      splashBackground = "rgb(18, 19, 22)";
    });

    patchMinimizeToTray = pkgs.writers.writePython3 "patch-vesktop-settings" {} ''
      import json
      import sys

      settings_path = sys.argv[1]

      with open(settings_path, "r") as f:
          data = json.load(f)

      data["minimizeToTray"] = False

      with open(settings_path, "w") as f:
          json.dump(data, f, indent=2)
    '';
  in {
    home-manager.users.${username} = {
      lib,
      pkgs,
      ...
    }: {
      imports = [inputs.nixcord.homeModules.nixcord];

      programs.nixcord = {
        enable = true;
        discord.enable = false;
        vesktop.enable = true;
        config = {
          autoUpdate = false;
          autoUpdateNotification = false;
          plugins = {
            # Add plugins here as needed, for example:
            # clearURLs.enable = true;
            # noTrack.enable = true;
            # callTimer.enable = true;
          };
        };
      };

      home.activation.vesktopSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "$HOME/.config/vesktop/themes"
        mkdir -p "$HOME/.config/vesktop/settings"

        SETTINGS="$HOME/.config/vesktop/settings.json"
        VENCORD_SETTINGS="$HOME/.config/vesktop/settings/settings.json"

        # Patch or seed vesktop settings
        if [ -f "$SETTINGS" ] && [ ! -L "$SETTINGS" ]; then
          ${patchMinimizeToTray} "$SETTINGS"
        else
          rm -f "$SETTINGS"
          ${pkgs.coreutils}/bin/install -m 644 ${vesktopSettingsFallback} "$SETTINGS"
        fi

        # Make Vencord settings writable for Noctalia
        if [ -L "$VENCORD_SETTINGS" ]; then
          STORE_VENCORD=$(readlink "$VENCORD_SETTINGS")
          rm "$VENCORD_SETTINGS"
          ${pkgs.coreutils}/bin/install -m 644 "$STORE_VENCORD" "$VENCORD_SETTINGS"
        fi

        # Seed Noctalia theme files if they don't exist
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