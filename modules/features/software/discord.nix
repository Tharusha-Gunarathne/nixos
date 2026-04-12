{inputs, ...}: {
  flake.nixosModules.discord = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.username;

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
          plugins = {};
        };
      };

      home.activation.vesktopSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "$HOME/.config/vesktop/themes"
        mkdir -p "$HOME/.config/vesktop/settings"

        SETTINGS="$HOME/.config/vesktop/settings.json"

        rm -f "$SETTINGS.backup"

        if [ -f "$SETTINGS" ] && [ ! -L "$SETTINGS" ]; then
          ${patchMinimizeToTray} "$SETTINGS"
        else
          rm -f "$SETTINGS"
          ${pkgs.coreutils}/bin/install -m 644 ${vesktopSettingsFallback} "$SETTINGS"
        fi
      '';
    };
  };
}