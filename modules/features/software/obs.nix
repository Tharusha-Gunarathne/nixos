{...}: {
  flake.nixosModules.obs = {
    config,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
  in {
    home-manager.users.${username} = {
      pkgs,
      lib,
      ...
    }: {
      home.packages = with pkgs; [
        obs-studio
      ];

      home.activation.obsCanvasSize = lib.hm.dag.entryAfter ["writeBoundary"] ''
        for ini in "$HOME/.config/obs-studio/basic/profiles/"*/basic.ini; do
          [ -f "$ini" ] || continue
          ${pkgs.gnused}/bin/sed -i -e 's/^BaseCX=.*/BaseCX=2560/' -e 's/^BaseCY=.*/BaseCY=1600/' -e 's/^OutputCX=.*/OutputCX=2560/' -e 's/^OutputCY=.*/OutputCY=1600/' "$ini"
        done
      '';
    };
  };
}
