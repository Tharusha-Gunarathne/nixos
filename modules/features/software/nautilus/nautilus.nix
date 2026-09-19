{...}: {
  flake.nixosModules.nautilus = {
    pkgs,
    lib,
    config,
    ...
  }: let
    username = config.myConfig.primaryUser;
    sourceDir = ./extensions;
    extensionFiles = builtins.attrNames (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".py" name)
      (builtins.readDir sourceDir)
    );
  in {
    # Nautilus hardcodes a 12s inactivity timeout, so the background
    # `--gapplication-service` instance exits shortly after login and every
    # launch pays full cold-start cost. Make it effectively infinite so the
    # prewarmed instance stays resident; `nautilus -q` still quits it.
    nixpkgs.overlays = [
      (final: prev: {
        nautilus = prev.nautilus.overrideAttrs (old: {
          postPatch =
            (old.postPatch or "")
            + ''
              substituteInPlace src/nautilus-application.c \
                --replace-fail '"inactivity-timeout", 12000' '"inactivity-timeout", G_MAXINT'
            '';
        });
      })
    ];

    environment.systemPackages = with pkgs; [
      nautilus
      nautilus-python
      gvfs
      glib
      xdg-utils
      gnome-terminal
    ];

    services.gvfs.enable = true;
    services.tumbler.enable = true;
    programs.dconf.enable = true;

    programs.nautilus-open-any-terminal = {
      enable = true;
      terminal = "kitty";
    };

    environment.pathsToLink = ["/share/nautilus-python/extensions"];

    environment.sessionVariables.NAUTILUS_4_EXTENSION_DIR = "${pkgs.nautilus-python}/lib/nautilus/extensions-4";

    home-manager.users.${username} = {...}: {
      xdg.dataFile = builtins.listToAttrs (map (name: {
          name = "nautilus-python/extensions/${name}";
          value = {source = sourceDir + "/${name}";};
        })
        extensionFiles);

      systemd.user.services.gvfs-daemon-prewarm = {
        Unit = {
          Description = "Pre-warm GVFS daemon for fast Nautilus first launch";
          After = ["graphical-session.target"];
          PartOf = ["graphical-session.target"];
        };
        Service = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = "${pkgs.glib}/bin/gio mount -li";
        };
        Install.WantedBy = ["graphical-session.target"];
      };

      systemd.user.services.nautilus-prewarm = {
        Unit = {
          Description = "Pre-warm Nautilus for fast first launch";
          After = ["graphical-session.target" "gvfs-daemon-prewarm.service"];
          PartOf = ["graphical-session.target"];
          Wants = ["gvfs-daemon-prewarm.service"];
        };
        Service = {
          Type = "simple";  # stays running, not oneshot
          ExecStart = "${pkgs.nautilus}/bin/nautilus --gapplication-service";
          # systemd's user environment lacks session variables, so pass the
          # extension dir explicitly or python extensions won't load.
          Environment = ["NAUTILUS_4_EXTENSION_DIR=${pkgs.nautilus-python}/lib/nautilus/extensions-4"];
          Restart = "always";
          RestartSec = "2s";
        };
        Install.WantedBy = ["graphical-session.target"];
      };
    };
  };
}