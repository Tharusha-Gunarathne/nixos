{inputs, ...}: {
  flake.nixosModules.displayManager = {pkgs, ...}: let
    # Change this to any folder name under qylock/themes, e.g. "clockwork", "winter", "enfield".
    themeName = "clockwork";
    # Only applies when themeName = "clockwork".
    clockworkMode = "light"; # or "light"

    qylockPin = inputs.sources.sourcePins.qylock;
    qylockSrc = pkgs.fetchFromGitHub qylockPin;

    qylockSddmTheme = pkgs.stdenvNoCC.mkDerivation {
      pname = "sddm-theme-qylock-${themeName}";
      version = "2026-04-17";
      src = qylockSrc;
      dontBuild = true;

      installPhase = ''
        runHook preInstall

        themeDir="$out/share/sddm/themes/${themeName}"
        mkdir -p "$themeDir"
        cp -r "$src/themes/${themeName}/." "$themeDir/"

        # Keep Clockwork-specific defaults declarative when that theme is selected.
        if [ "${themeName}" = "clockwork" ] && [ -f "$themeDir/theme.conf" ]; then
          ${pkgs.gnused}/bin/sed -i "s/^themeMode=.*/themeMode=${clockworkMode}/" "$themeDir/theme.conf"
          ${pkgs.gnused}/bin/sed -i "s/^enableWindup=.*/enableWindup=true/" "$themeDir/theme.conf"
        fi

        runHook postInstall
      '';
    };
  in {
    services.greetd.enable = false;

    services.displayManager.sddm = {
      enable = true;
      # X11 greeter is generally more reliable for pointer support across hardware.
      wayland.enable = false;

      theme = "${qylockSddmTheme}/share/sddm/themes/${themeName}";

      settings = {
        Theme = {
          CursorTheme = "Bibata-Modern-Classic";
          CursorSize = 24;
        };
      };
      extraPackages = with pkgs; [
        qt6.qtdeclarative
        qt6.qt5compat
        qt6.qtsvg
        qt6.qtmultimedia
        gst_all_1.gstreamer
        gst_all_1.gst-plugins-base
        gst_all_1.gst-plugins-good
        gst_all_1.gst-plugins-bad
        gst_all_1.gst-plugins-ugly
      ];
    };

    services.xserver.enable = true;

    environment.systemPackages = [qylockSddmTheme];

    services.seatd.enable = true;
  };
}
