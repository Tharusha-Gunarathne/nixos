{...}: {
  flake.nixosModules.ferdium = {config, ...}: let
    username = config.myConfig.primaryUser;
  in {
    home-manager.users.${username} = {
      lib,
      pkgs,
      ...
    }: {
      home.packages = [pkgs.ferdium];

      # Prevent Ferdium from silently re-enabling autostart.
      home.activation.disableFerdiumAutostart = lib.hm.dag.entryAfter ["writeBoundary"] ''
        rm -f "$HOME/.config/autostart/.ferdium-wrapped.desktop"
        rm -f "$HOME/.config/autostart/ferdium.desktop"
      '';
    };
  };
}
