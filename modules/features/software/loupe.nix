{...}: {
  flake.nixosModules.loupe = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
  in {
    environment.systemPackages = [pkgs.loupe];

    home-manager.users.${username} = {...}: {
      xdg.mimeApps.defaultApplications = {
        "image/jpeg" = ["org.gnome.Loupe.desktop"];
        "image/jpg" = ["org.gnome.Loupe.desktop"];
        "image/png" = ["org.gnome.Loupe.desktop"];
        "image/gif" = ["org.gnome.Loupe.desktop"];
        "image/webp" = ["org.gnome.Loupe.desktop"];
        "image/tiff" = ["org.gnome.Loupe.desktop"];
        "image/bmp" = ["org.gnome.Loupe.desktop"];
        "image/svg+xml" = ["org.gnome.Loupe.desktop"];
        "image/avif" = ["org.gnome.Loupe.desktop"];
        "image/heic" = ["org.gnome.Loupe.desktop"];
        "image/heif" = ["org.gnome.Loupe.desktop"];
      };

      dconf.settings."org/gnome/desktop/default-applications" = {
        viewer = "org.gnome.Loupe.desktop";
      };
    };
  };
}
