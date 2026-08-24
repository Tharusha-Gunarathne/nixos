{inputs, ...}: {
  flake.nixosModules.noctaliaPlugins = {
    config,
    lib,
    ...
  }: let
    pluginsToEnable = [
      "noctalia/notes"
      "noctalia/timer"
      "noctalia/wallpaper_depth"
      "noctalia/bitwarden"
      "alexander/screen-toolkit"
      "icefish/phone-operate"
      "raycursive/niri-displays"
      "kenn/keybind-cheatsheet"
    ];
  in {
    config = lib.mkIf config.myConfig.shell.noctalia {
      home-manager.users.${config.myConfig.primaryUser} = {config, lib, ...}: {
        xdg.configFile."noctalia/config.toml".text = ''
          [[plugins.source]]
          name = "official"
          kind = "path"
          location = "${inputs.noctalia.inputs.noctalia-official-plugins}"

          [[plugins.source]]
          name = "community"
          kind = "path"
          location = "${inputs.noctalia.inputs.noctalia-community-plugins}"
        '';

        home.activation.noctaliaPluginsEnable = lib.hm.dag.entryAfter ["writeBoundary"] ''
          export PATH="${config.home.profileDirectory}/bin:$PATH"

          if ! command -v noctalia >/dev/null 2>&1; then
            echo "[noctalia-plugins] noctalia binary not found on PATH, skipping"
          else
            PLUGINS_WANTED="${lib.concatStringsSep " " pluginsToEnable}"
            CURRENT=$(noctalia msg plugins list 2>/dev/null)

            for p in $PLUGINS_WANTED; do
              if echo "$CURRENT" | grep -qE "^$p .*enabled\$"; then
                echo "[noctalia-plugins] $p already enabled, skipping"
              else
                ENABLE_OUT=$(noctalia msg plugins enable "$p" 2>&1) || true
                echo "[noctalia-plugins] enabling $p: $ENABLE_OUT"
              fi
            done

            for i in $(seq 1 60); do
              CURRENT=$(noctalia msg plugins list 2>/dev/null)
              MISSING=0
              for p in $PLUGINS_WANTED; do
                echo "$CURRENT" | grep -qE "^$p .*enabled\$" || MISSING=1
              done
              if [ "$MISSING" -eq 0 ]; then
                echo "[noctalia-plugins] all enabled after ''${i}s"
                break
              fi
              [ "$i" -eq 60 ] && echo "[noctalia-plugins] timed out after 60s, some plugins may still be exporting"
              sleep 1
            done
          fi
        '';
      };
    };
  };
}