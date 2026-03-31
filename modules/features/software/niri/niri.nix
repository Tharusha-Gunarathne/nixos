{ self, ... }: {
  flake.nixosModules.niri = { config, lib, ... }:
  let
    username = config.myConfig.username;
  in {
    programs.niri.enable = true;

    home-manager.users.${username} = { config, lib, ... }: {
      home.activation.noctaliaNiriConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${config.xdg.configHome}/niri"
        if [ ! -f "${config.xdg.configHome}/niri/noctalia.kdl" ]; then
          touch "${config.xdg.configHome}/niri/noctalia.kdl"
        fi
      '';

      xdg.configFile."niri/config.kdl".source = ./config.kdl;
    };
  };
}
