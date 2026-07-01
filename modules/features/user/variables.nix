{...}: {
  flake.nixosModules.variables = {config, ...}: let
    username = config.myConfig.primaryUser;
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

      systemd.user.sessionVariables = {
        QT_QPA_PLATFORMTHEME = "qt6ct";
        XDG_DATA_DIRS = "/home/${username}/.local/share:/run/current-system/sw/share:/etc/profiles/per-user/${username}/share";
        XDG_CURRENT_DESKTOP = "GNOME";
        ICON_THEME = "Papirus-Dark";
      };
    };
  };
}
