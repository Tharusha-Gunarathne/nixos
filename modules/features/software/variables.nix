{self, ...}: {
  flake.nixosModules.variables = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.username;
  in {
    home-manager.users.${username} = {...}: {
      home.sessionVariables = {
        LIBVA_DRIVER_NAME = "nvidia";
        XDG_SESSION_TYPE = "wayland";
        GBM_BACKEND = "nvidia-drm";
        __GLX_VENDOR_LIBRARY_NAME = "nvidia";
        WLR_NO_HARDWARE_CURSORS = "1";
        NIXOS_OZONE_WL = "1";
        GTK_THEME = "Adwaita-dark";
        GI_TYPELIB_PATH = "/run/current-system/sw/lib/girepository-1.0";
        QT_QPA_PLATFORM = "wayland";
        QT_PLUGIN_PATH = "${pkgs.qt6.qtbase}/lib/qt-6/plugins:${pkgs.qt6.qtwayland}/lib/qt-6/plugins";
      };
    };
  };
}
