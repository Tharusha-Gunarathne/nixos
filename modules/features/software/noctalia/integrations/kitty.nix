{...}: {
  flake.nixosModules.noctaliaKitty = {
    config,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
    shell = config.myConfig.shell;
  in {
    config = lib.mkMerge [
      (lib.mkIf shell.noctalia {
        home-manager.users.${username} = {
          config,
          lib,
          ...
        }: {
          home.activation.kittyNoctaliaTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
            mkdir -p "${config.xdg.configHome}/kitty/themes"
            if [ ! -f "${config.xdg.configHome}/kitty/themes/noctalia.conf" ]; then
              touch "${config.xdg.configHome}/kitty/themes/noctalia.conf"
            fi
          '';
          programs.kitty.extraConfig = "include themes/noctalia.conf";
        };
      })

      (lib.mkIf (!shell.noctalia) {
        home-manager.users.${username} = {
          config,
          lib,
          ...
        }: {
          programs.kitty.extraConfig = lib.mkForce "";
          home.activation.kittyNoctaliaCleanup = lib.hm.dag.entryAfter ["writeBoundary"] ''
            rm -f "${config.xdg.configHome}/kitty/themes/noctalia.conf"
          '';
        };
      })
    ];
  };
}
