{...}: {
  flake.nixosModules.niri = {
    config,
    lib,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    shell = config.myConfig.shell;
    configPath = "${config.myConfig.repoRoot}/modules/features/software/niri/config.kdl";
    # displayTvOnly = pkgs.writeShellScriptBin "display-tv-only" ''
    #   set -euo pipefail
    #   NIRI="${pkgs.niri}/bin/niri"
    #   outputs="$($NIRI msg outputs)"
    #   names="$(printf '%s\n' "$outputs" | ${pkgs.gnused}/bin/sed -n 's/^Output ".*" (\([^)]*\)).*/\1/p')"
    #   internal="$(printf '%s\n' "$names" | ${pkgs.gnugrep}/bin/grep -E '^(eDP|LVDS)' | head -n1 || true)"
    #   externals="$(printf '%s\n' "$names" | ${pkgs.gnugrep}/bin/grep -Ev '^(eDP|LVDS)' || true)"
    #   tv="$(printf '%s\n' "$externals" | head -n1 || true)"
    #   if [ -z "$tv" ]; then
    #     echo "No external display detected. Plug in HDMI first."
    #     exit 1
    #   fi
    #   printf '%s\n' "$externals" | while read -r out; do
    #     [ -n "$out" ] || continue
    #     $NIRI msg output "$out" off >/dev/null 2>&1 || true
    #   done
    #   $NIRI msg output "$tv" on >/dev/null 2>&1 || true
    #   $NIRI msg output "$tv" scale 1.0 >/dev/null 2>&1 || true
    #   $NIRI msg action focus-monitor "$tv" >/dev/null 2>&1 || true
    #   if [ -n "$internal" ]; then
    #     $NIRI msg output "$internal" off >/dev/null 2>&1 || true
    #   fi
    #   echo "Switched to TV-only output: $tv"
    # '';
    # displayLaptopOnly = pkgs.writeShellScriptBin "display-laptop-only" ''
    #   set -euo pipefail
    #   NIRI="${pkgs.niri}/bin/niri"
    #   outputs="$($NIRI msg outputs)"
    #   names="$(printf '%s\n' "$outputs" | ${pkgs.gnused}/bin/sed -n 's/^Output ".*" (\([^)]*\)).*/\1/p')"
    #   internal="$(printf '%s\n' "$names" | ${pkgs.gnugrep}/bin/grep -E '^(eDP|LVDS)' | head -n1 || true)"
    #   externals="$(printf '%s\n' "$names" | ${pkgs.gnugrep}/bin/grep -Ev '^(eDP|LVDS)' || true)"
    #   if [ -z "$internal" ]; then
    #     echo "No internal display found."
    #     exit 1
    #   fi
    #   $NIRI msg output "$internal" on >/dev/null 2>&1 || true
    #   $NIRI msg action focus-monitor "$internal" >/dev/null 2>&1 || true
    #   printf '%s\n' "$externals" | while read -r out; do
    #     [ -n "$out" ] || continue
    #     $NIRI msg output "$out" off >/dev/null 2>&1 || true
    #   done
    #   echo "Switched to laptop-only output: $internal"
    # '';
  in {
    programs.niri.enable = true;

    home-manager.users.${username} = {
      config,
      lib,
      pkgs,
      ...
    }: {
      # home.packages = [
      #   displayTvOnly
      #   displayLaptopOnly
      # ];

      xdg.configFile."niri/config.kdl" = {
        source = config.lib.file.mkOutOfStoreSymlink "${configPath}";
      };

      home.activation.niriCleanupShellIncludes = lib.hm.dag.entryAfter ["writeBoundary"] ''
        NIRI_CONFIG="${configPath}"
        if [ -f "$NIRI_CONFIG" ] && [ "${
          if shell.noctalia
          then "true"
          else "false"
        }" != "true" ]; then
          ${pkgs.gnused}/bin/sed -i '/include "\.\/noctalia\.kdl"/d' "$NIRI_CONFIG"
        fi
      '';
    };
  };
}
