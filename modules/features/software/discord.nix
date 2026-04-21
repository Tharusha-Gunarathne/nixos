{ ... }: {
  flake.nixosModules.discord = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;

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
      inputs,
      pkgs,
      lib,
      ...
    }: {
      imports = [ inputs.nixcord.homeModules.nixcord ];

      programs.nixcord = {
        enable = true;
        discord.enable = false;
        vesktop.enable = true;

        config = {
          autoUpdate = false;
          autoUpdateNotification = false;
          plugins = {};
        };
      };

      xdg.configFile."vesktop/themes/.keep".text = "";
      xdg.configFile."vesktop/settings/.keep".text = "";

      # Optional: ensure settings.json exists declaratively
      xdg.configFile."vesktop/settings.json".source = vesktopSettingsFallback;

      home.activation.vesktopSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
        SETTINGS="$HOME/.config/vesktop/settings.json"

        # Only patch if file exists and is not a symlink
        if [ -f "$SETTINGS" ] && [ ! -L "$SETTINGS" ]; then
          ${patchMinimizeToTray} "$SETTINGS"
        fi
      '';
    };
  };
}