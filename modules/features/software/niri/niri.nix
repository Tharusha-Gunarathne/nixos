{inputs, ...}: {
  flake.nixosModules.niri = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    shell = config.myConfig.shell;
    configPath = "${config.myConfig.repoRoot}/modules/features/software/niri/config.kdl";
    libdisplayInfo0_2Pin = inputs.sources.sourcePins.libdisplayInfo0_2;    
  in {
    # Apply the overlay so pkgs.niri-stable exists
    nixpkgs.overlays = [
      inputs.niri-flake.overlays.niri
      (final: prev: {
        libdisplay-info_0_2 = prev.libdisplay-info.overrideAttrs (old: {
          version = libdisplayInfo0_2Pin.rev;
          src = prev.fetchFromGitLab {
            inherit (libdisplayInfo0_2Pin) domain owner repo rev hash;
          };
        });
      })
    ];

    programs.niri = {
      enable = true;
      package = pkgs.niri-unstable; # v26.04 from niri-flake's cache, no compilation
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
          ${pkgs.gnused}/bin/sed -i '/include "\.\/noctalia\.kdl"/d' "$NIRI_CONFIG"
        fi
      '';
    };
  };
}
