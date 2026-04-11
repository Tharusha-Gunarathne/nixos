{inputs, ...}: {
  flake.nixosModules.spotify = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.username;

    spicePkgs = inputs.spicetify-nix.legacyPackages.${pkgs.stdenv.hostPlatform.system};

    comfySrc = pkgs.fetchFromGitHub {
      owner = "Comfy-Themes";
      repo = "Spicetify";
      rev = "32ff101e27cfd33d85b7cc587f7f95db6b2df8b0";
      hash = "sha256-sqvmSXJMLE2in/cB8ZIJE/t4J5D0PKRddWECdYJjgX0=";
    };

    workDir = "/home/${username}/.local/share/spotify-spiced";

    # Absolute store path avoids PATH/profile resolution issues.
    spicetifyBin = "${pkgs.spicetify-cli}/bin/spicetify";

    # Noctalia hook: update theme without launching Spotify if it is closed.
    # If Spotify is already running, allow restart so new colors apply immediately.
    spicetifyColorHook = pkgs.writeShellScriptBin "spicetify-noctalia-color-hook" ''
      set -euo pipefail
      SPICE="${spicetifyBin}"
      WORK="${workDir}"

      if ${pkgs.procps}/bin/pgrep -f "$WORK/.spotify-wrapped" >/dev/null 2>&1; then
        "$SPICE" backup apply >/dev/null 2>&1 || "$SPICE" apply >/dev/null 2>&1 || true
      else
        "$SPICE" backup apply -n >/dev/null 2>&1 || "$SPICE" apply -n >/dev/null 2>&1 || true
      fi
    '';

    # Bootstrap + enforce: keeps a writable Spotify copy, ensures Comfy theme
    # and Marketplace app exist, and reapplies configuration when required.
    bootstrapScript = pkgs.writeShellScript "spicetify-bootstrap" ''
      set -euo pipefail
      SPICE="${spicetifyBin}"
      WORK="${workDir}"
      SPICE_CFG="$HOME/.config/spicetify"
      MARKET_DIR="$SPICE_CFG/CustomApps/marketplace"
      THEME_DIR="$SPICE_CFG/Themes/Comfy"
      SPICE_INI="$SPICE_CFG/config-xpui.ini"
      STATE_FILE="$WORK/.spicetify-state"
      TARGET_VERSION="${pkgs.spotify.version}"
      NEEDS_APPLY=0

      mkdir -p "$WORK"
      mkdir -p "$SPICE_CFG"

      # Refresh writable Spotify files on first run or package version change.
      if [ ! -x "$WORK/spotify" ] || [ ! -f "$STATE_FILE" ] || ! grep -qx "$TARGET_VERSION" "$STATE_FILE"; then
        echo "[spicetify] Preparing writable Spotify (${pkgs.spotify.version})..."
        ${pkgs.coreutils}/bin/rm -rf "$WORK"
        mkdir -p "$WORK"
        ${pkgs.coreutils}/bin/cp -r "${pkgs.spotify}/share/spotify/." "$WORK/"
        chmod -R u+w "$WORK"
        NEEDS_APPLY=1
      fi

      # The copied launcher from nixpkgs points to the immutable store binary.
      # Rewrite only the final exec target so it runs the writable local copy.
      if [ -f "$WORK/spotify" ]; then
        ${pkgs.gnused}/bin/sed -i -E \
          "s|exec -a \"\\\$0\" \"/nix/store/[^\"]+/share/spotify/\\.spotify-wrapped\"|exec -a \"\\\$0\" \"$WORK/.spotify-wrapped\"|" \
          "$WORK/spotify"
      fi

      if [ ! -f "$THEME_DIR/user.css" ]; then
        ${pkgs.coreutils}/bin/rm -rf "$THEME_DIR"
        mkdir -p "$THEME_DIR"
        ${pkgs.coreutils}/bin/cp -r "${comfySrc}/Comfy/." "$THEME_DIR/"
        chmod -R u+w "$THEME_DIR"
        NEEDS_APPLY=1
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
      "$SPICE" config current_theme    Comfy
      "$SPICE" config color_scheme     Comfy
      "$SPICE" config inject_css       1
      "$SPICE" config replace_colors   1
      "$SPICE" config overwrite_assets 1
      "$SPICE" config inject_theme_js  1
      "$SPICE" config custom_apps      marketplace

      # spicetify config can keep stale pipe-separated values; normalize to exactly marketplace.
      if [ -f "$SPICE_INI" ]; then
        ${pkgs.gnused}/bin/sed -i -E \
          's|^custom_apps\s*=.*$|custom_apps           = marketplace|' \
          "$SPICE_INI"
      fi

      # Re-apply when first set up, after upgrades, or when config was reset.
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
      comment = "Spotify with Spicetify + Noctalia theme sync";
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
        spicetifyColorHook
        desktopEntry
      ];

      xdg.mimeApps.defaultApplications."x-scheme-handler/spotify" = ["spotify.desktop"];

      # Cleanup from earlier user-template approach; built-in template is now used.
      home.activation.noctaliaTemplateCleanup = lib.hm.dag.entryAfter ["writeBoundary"] ''
        rm -f "$HOME/.config/noctalia/user-templates.toml"
        rm -f "$HOME/.config/noctalia/templates/comfy-color.ini.tmpl"
      '';
    };
  };
}
