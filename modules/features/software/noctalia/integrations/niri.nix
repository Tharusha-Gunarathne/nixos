{...}: {
  flake.nixosModules.noctaliaNiri = {
    config,
    lib,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    shell = config.myConfig.shell;
    configPath = "${config.myConfig.repoRoot}/modules/features/software/niri/config.kdl";
  in {
    config = lib.mkMerge [
      (lib.mkIf shell.noctalia {
        home-manager.users.${username} = {
          config,
          lib,
          pkgs,
          ...
        }: {
          home.activation.noctaliaNiriConfig = lib.hm.dag.entryAfter ["writeBoundary" "niriCleanupShellIncludes"] ''
            NOCTALIA_KDL="${config.xdg.configHome}/niri/noctalia.kdl"
            NIRI_CONFIG="${configPath}"
            INCLUDE_LINE='include "./noctalia.kdl"'

            mkdir -p "${config.xdg.configHome}/niri"
            if [ ! -f "$NOCTALIA_KDL" ]; then
              touch "$NOCTALIA_KDL"
            fi

            if ! ${pkgs.gnugrep}/bin/grep -qE '^[[:space:]]*include "\./noctalia\.kdl"[[:space:]]*$' "$NIRI_CONFIG"; then
              printf '\n%s\n' "$INCLUDE_LINE" >> "$NIRI_CONFIG"
              echo "[noctalia] Injected include into config.kdl"
            fi
          '';
        };
      })

      (lib.mkIf (!shell.noctalia) {
        home-manager.users.${username} = {
          config,
          lib,
          pkgs,
          ...
        }: {
          home.activation.noctaliaNiriCleanup = lib.hm.dag.entryAfter ["writeBoundary"] ''
            NIRI_CONFIG="${configPath}"

            if [ -f "$NIRI_CONFIG" ]; then
              ${pkgs.gnused}/bin/sed -i '/include "\.\/noctalia\.kdl"/d' "$NIRI_CONFIG"
            fi

            rm -f "${config.xdg.configHome}/niri/noctalia.kdl"
          '';
        };
      })
    ];
  };
}
