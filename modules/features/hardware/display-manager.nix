{...}: {
  flake.nixosModules.displayManager = {pkgs, ...}: let
    qylockSrc = builtins.fetchGit {
      url = "https://github.com/Darkkal44/qylock.git";
      rev = "6d676217daef421e1d4abdc99a9307c60ed0d49b";
    };

    qylockClockworkTheme = pkgs.stdenvNoCC.mkDerivation {
      pname = "sddm-theme-qylock-clockwork";
      version = "2026-04-17";
      src = qylockSrc;
      dontBuild = true;

      installPhase = ''
        runHook preInstall

        themeDir="$out/share/sddm/themes/clockwork"
        mkdir -p "$themeDir"
        cp -r "$src/themes/clockwork/." "$themeDir/"

        # Keep desired Clockwork defaults declarative.
        ${pkgs.gnused}/bin/sed -i 's/^themeMode=.*/themeMode=dark/' "$themeDir/theme.conf"
        ${pkgs.gnused}/bin/sed -i 's/^enableWindup=.*/enableWindup=true/' "$themeDir/theme.conf"

        runHook postInstall
      '';
    };
  in {
    services.greetd.enable = false;

    services.displayManager.sddm = {
      enable = true;
      wayland.enable = true;
      # Absolute path is supported by nixpkgs' sddm module and avoids package override issues.
      theme = "${qylockClockworkTheme}/share/sddm/themes/clockwork";
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

    environment.systemPackages = [qylockClockworkTheme];

    services.seatd.enable = true;
  };
}
