{...}: {
  flake.nixosModules.variables = {config, lib, pkgs, ...}: let
    username = config.myConfig.primaryUser;

    # Read the GitHub PAT from .env.local if the [github] section exists.
    # Same field nixSettings.nix already reads for /etc/nix/access-tokens.conf.
    # Falls back to "" so the module stays functional without one.
  in {
    home-manager.users.${username} = {...}: {
      xdg.userDirs = {
        enable = true;
        createDirectories = true;
        setSessionVariables = true; # add this line
        desktop = "$HOME/Desktop";
        download = "$HOME/Downloads";
        templates = "$HOME/Templates";
        publicShare = "$HOME/Public";
        documents = "$HOME/Documents";
        music = "$HOME/Music";
        pictures = "$HOME/Pictures";
        videos = "$HOME/Videos";
      };

      home.sessionPath = [
        "$HOME/.local/bin"
      ];

      home.sessionVariables = {
        LIBVA_DRIVER_NAME = "nvidia";
        XDG_SESSION_TYPE = "wayland";
        GBM_BACKEND = "nvidia-drm";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        WLR_NO_HARDWARE_CURSORS = "1";
        NIXOS_OZONE_WL = "1";
        GI_TYPELIB_PATH = "/run/current-system/sw/lib/girepository-1.0";
        QT_QPA_PLATFORMTHEME = "qt6ct";
        XDG_CURRENT_DESKTOP = "GNOME";
      };

      home.sessionVariablesExtra = ''
        if [ -r ${lib.escapeShellArg "${config.myConfig.repoRoot}/.env.local"} ]; then
          export GITHUB_PERSONAL_ACCESS_TOKEN="$(
            ${pkgs.python3}/bin/python3 ${../core/local-value.py} \
              ${lib.escapeShellArg "${config.myConfig.repoRoot}/.env.local"} github access_token
          )"
        fi
      '';

      systemd.user.sessionVariables = {
        QT_QPA_PLATFORMTHEME = "qt6ct";
        XDG_DATA_DIRS = "/home/${username}/.local/share:/run/current-system/sw/share:/etc/profiles/per-user/${username}/share";
        XDG_CURRENT_DESKTOP = "GNOME";
        ICON_THEME = "Papirus-Dark";
      };
    };
  };
}
