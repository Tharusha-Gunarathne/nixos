{...}: {
  flake.nixosModules.gtk = {
    pkgs,
    config,
    ...
  }: let
    username = config.myConfig.primaryUser;
    schemaDir = "${pkgs.gsettings-desktop-schemas}/share/gsettings-schemas/gsettings-desktop-schemas-${pkgs.gsettings-desktop-schemas.version}/glib-2.0/schemas";

    # Change this to any color from: papirus-folders -l --theme Papirus-Dark
    # e.g. adwaita, black, blue, bluegrey, breeze, brown, carmine, cyan, darkcyan, deeporange, green, grey, indigo, magenta, nordic, orange, palebrown, paleorange, pink, red, teal, violet, white, yellow, yaru ...
    folderColor = "nordic";
  in {
    environment.systemPackages = with pkgs; [
      adwaita-icon-theme
      papirus-icon-theme
      adw-gtk3
      gsettings-desktop-schemas
      bibata-cursors
      papirus-folders
    ];

    programs.dconf.enable = true;

    environment.sessionVariables.GSETTINGS_SCHEMA_DIR = schemaDir;

    environment.pathsToLink = [
      "/share/gsettings-schemas/gsettings-desktop-schemas-${pkgs.gsettings-desktop-schemas.version}"
    ];

    home-manager.users.${username} = {
      pkgs,
      lib,
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
          name = "Bibata-Modern-Ice";
          package = pkgs.bibata-cursors;
          size = 20;
        };
        gtk4.theme = null;
      };

      home.pointerCursor = {
        name = "Bibata-Modern-Ice";
        package = pkgs.bibata-cursors;
        size = 20;
        gtk.enable = true;
        x11.enable = true;
      };

      dconf.settings."org/gnome/desktop/interface" = {
        color-scheme = "prefer-dark";
        gtk-theme = "adw-gtk3-dark";
        icon-theme = "Papirus-Dark";
        font-name = lib.mkForce "Ubuntu Sans 11";
        document-font-name = "Ubuntu Sans 11";
        monospace-font-name = "JetBrains Mono Nerd Font 10";
        cursor-theme = "Bibata-Modern-Ice";
        cursor-size = 20;
      };

      xdg.configFile."qt6ct/qt6ct.conf".text = ''
        [Appearance]
        icon_theme=Papirus-Dark
        style=adwaita-dark
        standard_dialogs=default
      
        [Fonts]
        fixed="JetBrainsMono Nerd Font,10,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
        general="Ubuntu Sans,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1"
      
        [Interface]
        activate_item_on_single_click=1
        buttonbox_layout=0
        cursor_flash_time=1000
        dialog_buttons_have_icons=1
        double_click_interval=400
        keyboard_scheme=2
        menus_have_icons=true
        show_shortcuts_in_context_menus=true
        toolbutton_style=4
        wheel_scroll_lines=3
      '';

      home.activation.papirusFolderColor = lib.hm.dag.entryAfter ["writeBoundary"] ''
        STORE_BASE="${pkgs.papirus-icon-theme}/share/icons/Papirus"
        STORE_DARK="${pkgs.papirus-icon-theme}/share/icons/Papirus-Dark"
        LOCAL_BASE="$HOME/.local/share/icons/Papirus"
        LOCAL_THEME="$HOME/.local/share/icons/Papirus-Dark"
        STATE_FILE="$HOME/.local/share/icons/.papirus-${folderColor}-state"
        TARGET_COLOR="${folderColor}"

        if [ ! -f "$STATE_FILE" ] || ! grep -qx "$STORE_DARK:$TARGET_COLOR" "$STATE_FILE"; then
          echo "[papirus-folders] Seeding writable Papirus and Papirus-Dark..."
          rm -rf "$LOCAL_BASE" "$LOCAL_THEME"
          mkdir -p "$HOME/.local/share/icons"
          ${pkgs.coreutils}/bin/cp -r "$STORE_BASE" "$LOCAL_BASE"
          ${pkgs.coreutils}/bin/cp -r "$STORE_DARK" "$LOCAL_THEME"
          chmod -R u+w "$LOCAL_BASE" "$LOCAL_THEME"
          export PATH="${lib.makeBinPath (with pkgs; [gawk coreutils gnused findutils])}:$PATH"
          ${pkgs.papirus-folders}/bin/papirus-folders -C "$TARGET_COLOR" --theme Papirus-Dark
          echo "$STORE_DARK:$TARGET_COLOR" > "$STATE_FILE"
          echo "[papirus-folders] Folder color set to $TARGET_COLOR"
        fi
      '';
    };
  };
}
