{...}: {
  flake.nixosModules.noctaliaNiri = {
    config,
    lib,
    pkgs,
    ...
  }: let
    username = config.myConfig.username;
    shell = config.myConfig.shell;
    configPath = "${config.myConfig.repoRoot}/modules/features/software/niri/config.kdl";
  in {
    config = lib.mkIf (shell == "noctalia") {
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

          if ! ${pkgs.gnugrep}/bin/grep -qF "$INCLUDE_LINE" "$NIRI_CONFIG"; then
            echo "" >> "$NIRI_CONFIG"
            echo "$INCLUDE_LINE" >> "$NIRI_CONFIG"
            echo "[noctalia] Injected include into config.kdl"
          fi
        '';
      };
    };
  };
}