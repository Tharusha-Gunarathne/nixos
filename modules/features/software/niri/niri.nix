{inputs, ...}: {
  flake.nixosModules.niri = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    shell = config.myConfig.shell;
    configPath = "${config.myConfig.repoRoot}/modules/features/software/niri/config.kdl";
  in {
    programs.niri = {
      enable = true;
      # Use the system dependency set so EGL/GBM match the installed GPU
      # driver. The flake's standalone cache uses an older graphics runtime.
      package = pkgs.niri-unstable;
    };

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
          ${pkgs.gnused}/bin/sed -i '/^[[:space:]]*include "\(\.\/\)\?noctalia\.kdl"[[:space:]]*$/d' "$NIRI_CONFIG"
        fi
      '';
    };
  };
}
