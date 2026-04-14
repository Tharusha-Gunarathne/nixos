{...}: {
  flake.nixosModules.gtk = {
    pkgs,
    config,
    ...
  }: let
    username = config.myConfig.primaryUser;
    schemaDir = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/gsettings-desktop-schemas-${pkgs.gsettings-desktop-schemas.version}/glib-2.0/schemas";
  in {
    environment.systemPackages = with pkgs; [
      adwaita-icon-theme
      papirus-icon-theme
      adw-gtk3                  # required by Noctalia for GTK theming
      gsettings-desktop-schemas
    ];

    programs.dconf.enable = true;

    environment.sessionVariables.GSETTINGS_SCHEMA_DIR = schemaDir;

    environment.pathsToLink = [
      "/share/gsettings-schemas/gsettings-desktop-schemas-${pkgs.gsettings-desktop-schemas.version}"
    ];

    home-manager.users.${username} = {
      pkgs,
      config,
      ...
    }: {
      gtk = {
        enable = true;
        font = {
          name = "Ubuntu Sans";
          size = 11;
          package = pkgs.ubuntu-sans;
        };
        theme = {
          name = "adw-gtk3-dark";
          package = pkgs.adw-gtk3;
        };
        iconTheme = {
          name = "Papirus-Dark";
          package = pkgs.papirus-icon-theme;
        };
        cursorTheme = {
          name = "Adwaita";
          package = pkgs.adwaita-icon-theme;
        };
        gtk4.theme = null;
      };

      dconf.settings."org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        gtk-theme = "adw-gtk3-dark";
        icon-theme = "Papirus-Dark";
        font-name = "Ubuntu Sans 11";
        document-font-name = "Ubuntu Sans 11";
        monospace-font-name = "JetBrainsMono Nerd Font 11";
      };
    };
  };
}