{ self, ... }: {
  flake.nixosModules.gtk = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      adwaita-icon-theme
      papirus-icon-theme
      gnome-themes-extra
    ];
  };

  flake.homeManagerModules.gtk = { pkgs, config, ... }: {
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
  };
}
