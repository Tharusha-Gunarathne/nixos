{...}: {
  flake.nixosModules.noctaliaKitty = {
    config,
    lib,
    pkgs,
    ...
  }: let
    username = config.myConfig.username;
    shell = config.myConfig.shell;
  in {
    config = lib.mkIf (shell == "noctalia") {
      home-manager.users.${username} = {
        config,
        lib,
        pkgs,
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
    };
  };
}