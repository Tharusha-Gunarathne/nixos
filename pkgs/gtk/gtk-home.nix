{ config, pkgs, inputs, ... }:
 
{
    gtk = {
        enable = true;
        font = {
        name = "Ubuntu Sans";
        size = 11;
        package = pkgs.ubuntu-sans;
        };
        theme = {
        name = "Adwaita-dark";
        package = pkgs.gnome-themes-extra;
        };
        iconTheme = {
        name = "Papirus-Dark";
        package = pkgs.papirus-icon-theme;
        };
        cursorTheme = {
        name = "Adwaita";
        package = pkgs.adwaita-icon-theme;
        };

        # Keep pre-26.05 behavior explicitly to avoid default-change warnings.
        gtk4.theme = config.gtk.theme;
    };

    dconf.settings = {
        "org/gnome/desktop/interface" = {
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