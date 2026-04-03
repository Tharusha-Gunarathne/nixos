{ self, ... }: {
  flake.nixosModules.gtk = { pkgs, config, ... }:
  let
    username = config.myConfig.username;
    schemaDir = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/gsettings-desktop-schemas-${pkgs.gsettings-desktop-schemas.version}/glib-2.0/schemas";
  in {
    environment.systemPackages = with pkgs; [
      adwaita-icon-theme
      papirus-icon-theme
      gnome-themes-extra
      gsettings-desktop-schemas
    ];

    programs.dconf.enable = true;

    environment.sessionVariables.GSETTINGS_SCHEMA_DIR = schemaDir;

    environment.pathsToLink = [
      "/share/gsettings-schemas/gsettings-desktop-schemas-${pkgs.gsettings-desktop-schemas.version}"
    ];

    home-manager.users.${username} = { pkgs, config, lib, ... }: {
      gtk = {
        enable = true;
        font = { name = "Ubuntu Sans"; size = 11; package = pkgs.ubuntu-sans; };
        theme = { name = "Adwaita-dark"; package = pkgs.gnome-themes-extra; };
        iconTheme = { name = "Papirus-Dark"; package = pkgs.papirus-icon-theme; };
        cursorTheme = { name = "Adwaita"; package = pkgs.adwaita-icon-theme; };
        gtk4.theme = config.gtk.theme;
      };

      dconf.settings."org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        gtk-theme = "Adwaita-dark";
        icon-theme = "Papirus-Dark";
        scaling-factor = 1;
        text-scaling-factor = 1.0;
        font-name = "Ubuntu Sans 11";
        document-font-name = "Ubuntu Sans 11";
        monospace-font-name = "JetBrainsMono Nerd Font 11";
      };

      home.file.".config/gtk-3.0/gtk.css".text = ''
        @import url("noctalia.css");
      '';

      home.file.".config/gtk-4.0/gtk.css".text = ''
        @import url("noctalia.css");
      '';
    };
  };
}