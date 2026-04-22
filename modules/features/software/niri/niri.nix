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
  in {
    programs.niri.enable = true;

    home-manager.users.${username} = {
      config,
      lib,
      pkgs,
      ...
    }: {
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
