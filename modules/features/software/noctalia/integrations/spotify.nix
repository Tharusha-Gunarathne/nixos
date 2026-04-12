{inputs, ...}: {
  flake.nixosModules.noctaliaSpotify = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.username;
    shell = config.myConfig.shell;

    spicetifyBin = "${pkgs.spicetify-cli}/bin/spicetify";

    comfySrc = pkgs.fetchFromGitHub {
      owner = "Comfy-Themes";
      repo = "Spicetify";
      rev = "32ff101e27cfd33d85b7cc587f7f95db6b2df8b0";
      hash = "sha256-sqvmSXJMLE2in/cB8ZIJE/t4J5D0PKRddWECdYJjgX0=";
    };

    spicetifyColorHook = pkgs.writeShellScriptBin "spicetify-noctalia-color-hook" ''
      set -euo pipefail
      SPICE="${spicetifyBin}"
      PGREP="${pkgs.procps}/bin/pgrep"
      SPICE_INI="$HOME/.config/spicetify/config-xpui.ini"
      NIRI="${pkgs.niri}/bin/niri"
      JQ="${pkgs.jq}/bin/jq"
      WTYPE="${pkgs.wtype}/bin/wtype"

      reload_spotify_window() {
        focused_id="$($NIRI msg -j focused-window 2>/dev/null | $JQ -r '.id // empty' || true)"
        spotify_id="$($NIRI msg -j windows 2>/dev/null | $JQ -r 'map(select(.app_id == "spotify")) | first | .id // empty' || true)"

        if [ -n "$spotify_id" ]; then
          if [ -n "$focused_id" ] && [ "$focused_id" != "$spotify_id" ]; then
            $NIRI msg action focus-window --id "$spotify_id" >/dev/null 2>&1 || true
          fi

          $WTYPE -k F5 >/dev/null 2>&1 || true
          $WTYPE -M ctrl -M shift r -m shift -m ctrl >/dev/null 2>&1 || true

          if [ -n "$focused_id" ] && [ "$focused_id" != "$spotify_id" ]; then
            $NIRI msg action focus-window --id "$focused_id" >/dev/null 2>&1 || true
          fi
        fi
      }

      if [ -f "$SPICE_INI" ]; then
        ${pkgs.gnused}/bin/sed -i -E \
          's|^custom_apps\s*=.*$|custom_apps           = marketplace|' \
          "$SPICE_INI"
      fi

      if "$PGREP" -f 'spotify|\.spotify-wrapped' >/dev/null 2>&1; then
        if ! "$SPICE" -n -s -a -e refresh >/dev/null 2>&1; then
          "$SPICE" -n apply >/dev/null 2>&1 || "$SPICE" -n backup apply >/dev/null 2>&1 || true
          "$SPICE" -n -s -a -e refresh >/dev/null 2>&1 || "$SPICE" -n -s refresh >/dev/null 2>&1 || true
        fi
        reload_spotify_window
      else
        "$SPICE" -n apply >/dev/null 2>&1 || "$SPICE" -n backup apply >/dev/null 2>&1 || true
      fi
    '';

    comfySetupScript = pkgs.writeShellScript "spicetify-comfy-setup" ''
      set -euo pipefail
      SPICE="${spicetifyBin}"
      SPICE_CFG="$HOME/.config/spicetify"
      THEME_DIR="$SPICE_CFG/Themes/Comfy"
      SPICE_INI="$SPICE_CFG/config-xpui.ini"
      NEEDS_APPLY=0

      if [ ! -f "$THEME_DIR/user.css" ]; then
        ${pkgs.coreutils}/bin/rm -rf "$THEME_DIR"
        mkdir -p "$THEME_DIR"
        ${pkgs.coreutils}/bin/cp -r "${comfySrc}/Comfy/." "$THEME_DIR/"
        chmod -R u+w "$THEME_DIR"
        NEEDS_APPLY=1
      fi

      "$SPICE" config current_theme Comfy
      "$SPICE" config color_scheme  Comfy

      if [ -f "$SPICE_INI" ]; then
        ${pkgs.gnused}/bin/sed -i -E \
          's|^custom_apps\s*=.*$|custom_apps           = marketplace|' \
          "$SPICE_INI"
      fi

      if [ "$NEEDS_APPLY" -eq 1 ]; then
        "$SPICE" backup apply
      fi
    '';
  in {
    config = lib.mkIf (shell == "noctalia") {
      home-manager.users.${username} = {lib, ...}: {
        home.packages = [
          spicetifyColorHook
          pkgs.wtype
          pkgs.jq
        ];

        home.activation.noctaliaSpotifySetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
          ${comfySetupScript}
        '';

        home.activation.noctaliaTemplateCleanup = lib.hm.dag.entryAfter ["writeBoundary"] ''
          rm -f "$HOME/.config/noctalia/user-templates.toml"
          rm -f "$HOME/.config/noctalia/templates/comfy-color.ini.tmpl"
          rm -f "$HOME/.config/systemd/user/spicetify-watch.service"
          ${pkgs.systemd}/bin/systemctl --user daemon-reload || true
          ${pkgs.systemd}/bin/systemctl --user disable --now spicetify-watch.service || true
        '';
      };
    };
  };
}