{ self, ... }: {
  flake.nixosModules.niri = { ... }: {
    programs.niri.enable = true;
  };

  flake.homeManagerModules.niri = { lib, config, ... }: {
    home.activation.noctaliaNiriConfig = lib.hm.dag.entryAfter ["writeBoundary"] ''
      mkdir -p "${config.xdg.configHome}/niri"
      if [ ! -f "${config.xdg.configHome}/niri/noctalia.kdl" ]; then
        touch "${config.xdg.configHome}/niri/noctalia.kdl"
      fi
    '';

    xdg.configFile."niri/config.kdl".source = ./config.kdl;
  };
}
