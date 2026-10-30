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
    #
    # GTK 4.22.4 GtkDragSource leaves a stale drag timeout behind when a list
    # row is torn down, corrupting freed memory and segfaulting Nautilus while
    # large folders load (GNOME/gtk#8191, fixed in 4.22.5). Patch GTK only for
    # Nautilus so the rest of the system keeps the cached gtk4; drop this once
    # nixpkgs ships gtk4 >= 4.22.5.
    nixpkgs.overlays = [
      (final: prev: let
        gtk4 = prev.gtk4.overrideAttrs (old: {
          patches = (old.patches or []) ++ [./gtk-dragsource-uaf.patch];
        });
      in {
        nautilus =
          # Every gtk4 consumer Nautilus links must share the patched build,
          # otherwise the loader resolves the unpatched libgtk-4 first.
          (prev.nautilus.override {
            inherit gtk4;
            libadwaita = prev.libadwaita.override {inherit gtk4;};
            gnome-desktop = prev.gnome-desktop.override {inherit gtk4;};
            libportal-gtk4 = prev.libportal-gtk4.override {inherit gtk4;};
            libglycin-gtk4 = prev.libglycin-gtk4.override {inherit gtk4;};
            # The hook propagates its own gtk4, which lands first in RUNPATH.
            wrapGAppsHook4 = prev.wrapGAppsHook4.override {gtk3 = gtk4;};
          }).overrideAttrs (old: {
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
      xdg.dataFile =
        builtins.listToAttrs (map (name: {
            name = "nautilus-python/extensions/${name}";
            value = {source = sourceDir + "/${name}";};
          })
          extensionFiles)
        // {
          # Noctalia's dock D-Bus-activates DBusActivatable apps with a ~500ms
          # timeout, then falls back to Exec. The resident instance's first
          # window takes longer than that after login, so both paths fire and
          # two windows open. Drop DBusActivatable so launchers use Exec, which
          # still hands off to the resident instance without blocking the dock.
          "applications/org.gnome.Nautilus.desktop".source =
            pkgs.runCommand "org.gnome.Nautilus.desktop" {} ''
              sed '/^DBusActivatable=/d' \
                ${pkgs.nautilus}/share/applications/org.gnome.Nautilus.desktop > $out
            '';
        };

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
          # Exit 1 means another instance already owns org.gnome.Nautilus
          # (D-Bus activated or launched directly); retrying just loops.
          RestartPreventExitStatus = "1";
        };
        Install.WantedBy = ["graphical-session.target"];
      };
    };
  };
}