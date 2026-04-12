{inputs, ...}: {
  flake.nixosModules.spotify = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.username;
    shell = config.myConfig.shell;

    spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};

    workDir = "/home/${username}/.local/share/spotify-spiced";

    spicetifyBin = "${pkgs.spicetify-cli}/bin/spicetify";

    bootstrapScript = pkgs.writeShellScript "spicetify-bootstrap" ''
      set -euo pipefail
      SPICE="${spicetifyBin}"
      WORK="${workDir}"
      SPICE_CFG="$HOME/.config/spicetify"
      MARKET_DIR="$SPICE_CFG/CustomApps/marketplace"
      SPICE_INI="$SPICE_CFG/config-xpui.ini"
      STATE_FILE="$WORK/.spicetify-state"
      TARGET_VERSION="${pkgs.spotify.version}"
      NEEDS_APPLY=0

      mkdir -p "$WORK"
      mkdir -p "$SPICE_CFG"

      if [ ! -x "$WORK/spotify" ] || [ ! -f "$STATE_FILE" ] || ! grep -qx "$TARGET_VERSION" "$STATE_FILE"; then
        echo "[spicetify] Preparing writable Spotify (${pkgs.spotify.version})..."
        ${pkgs.coreutils}/bin/rm -rf "$WORK"
        mkdir -p "$WORK"
        ${pkgs.coreutils}/bin/cp -r "${pkgs.spotify}/share/spotify/." "$WORK/"
        chmod -R u+w "$WORK"
        NEEDS_APPLY=1
      fi

      if [ -f "$WORK/spotify" ]; then
        ${pkgs.gnused}/bin/sed -i -E \
          "s|exec -a \"\\\$0\" \"/nix/store/[^\"]+/share/spotify/\\.spotify-wrapped\"|exec -a \"\\\$0\" \"$WORK/.spotify-wrapped\"|" \
          "$WORK/spotify"
      fi

      if [ ! -f "$MARKET_DIR/index.js" ]; then
        ${pkgs.coreutils}/bin/rm -rf "$MARKET_DIR"
        mkdir -p "$MARKET_DIR"
        ${pkgs.coreutils}/bin/cp -r "${spicePkgs.apps.marketplace.src}/." "$MARKET_DIR/"
        chmod -R u+w "$MARKET_DIR"
        NEEDS_APPLY=1
      fi

      if [ ! -f "$SPICE_INI" ] || \
         ! ${pkgs.gnugrep}/bin/grep -Eq '^custom_apps\s*=\s*marketplace$' "$SPICE_INI"; then
        NEEDS_APPLY=1
      fi

      "$SPICE" config spotify_path     "$WORK"
      "$SPICE" config prefs_path       "$HOME/.config/spotify/prefs"
      "$SPICE" config inject_css       1
      "$SPICE" config replace_colors   1
      "$SPICE" config overwrite_assets 1
      "$SPICE" config inject_theme_js  1
      "$SPICE" config custom_apps      marketplace

      if [ -f "$SPICE_INI" ]; then
        ${pkgs.gnused}/bin/sed -i -E \
          's|^custom_apps\s*=.*$|custom_apps           = marketplace|' \
          "$SPICE_INI"
      fi

      if [ "$NEEDS_APPLY" -eq 1 ]; then
        "$SPICE" backup apply
      fi

      echo "$TARGET_VERSION" > "$STATE_FILE"
    '';

    spotifyWrapper = pkgs.writeShellScriptBin "spotify-noctalia" ''
      if ! ${bootstrapScript}; then
        echo "[spicetify] Bootstrap failed; falling back to stock Spotify."
        exec "${pkgs.spotify}/bin/spotify" "$@"
      fi

      if [ -x "${workDir}/spotify" ]; then
        exec "${workDir}/spotify" "$@"
      fi

      echo "[spicetify] Writable launcher missing; falling back to stock Spotify."
      exec "${pkgs.spotify}/bin/spotify" "$@"
    '';

    desktopEntry = pkgs.makeDesktopItem {
      name = "spotify";
      desktopName = "Spotify";
      genericName = "Music Player";
      comment = "Spotify with Spicetify + Marketplace";
      icon = "${pkgs.spotify}/share/spotify/icons/spotify-linux-128.png";
      exec = "${spotifyWrapper}/bin/spotify-noctalia %U";
      categories = ["Audio" "Music" "Player" "AudioVideo"];
      mimeTypes = ["x-scheme-handler/spotify"];
      startupWMClass = "spotify";
    };
  in {
    home-manager.users.${username} = {lib, ...}: {
      home.packages = [
        spotifyWrapper
        pkgs.spicetify-cli
        desktopEntry
      ];

      xdg.mimeApps.defaultApplications."x-scheme-handler/spotify" = ["spotify.desktop"];

      home.activation.spotifyCleanupShellTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
        SPICE="${spicetifyBin}"
        SPICE_INI="$HOME/.config/spicetify/config-xpui.ini"

        if [ "${shell}" != "noctalia" ] && [ -f "$SPICE_INI" ]; then
          ${pkgs.gnused}/bin/sed -i -E \
            's|^current_theme\s*=.*$|current_theme         = |' \
            "$SPICE_INI"
          ${pkgs.gnused}/bin/sed -i -E \
            's|^color_scheme\s*=.*$|color_scheme          = |' \
            "$SPICE_INI"
        fi
      '';
    };
  };
}