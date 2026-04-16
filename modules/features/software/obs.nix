{...}: {
  flake.nixosModules.obs = {
    config,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;

    displayX = 2560;
    displayY = 1600;
  in {
    home-manager.users.${username} = {
      pkgs,
      lib,
      ...
    }: {
      home.packages = with pkgs; [
        obs-studio
      ];

      # OBS Base and Output canvas size definition
      home.activation.obsCanvasSize = lib.hm.dag.entryAfter ["writeBoundary"] ''
        for ini in "$HOME/.config/obs-studio/basic/profiles/"*/basic.ini; do
          [ -f "$ini" ] || continue
          ${pkgs.gnused}/bin/sed -i -e 's/^BaseCX=.*/BaseCX=${displayX}/' -e 's/^BaseCY=.*/BaseCY=${displayY}/' -e 's/^OutputCX=.*/OutputCX=${displayX}/' -e 's/^OutputCY=.*/OutputCY=${displayY}/' "$ini"
        done
      '';
    };
  };
}
