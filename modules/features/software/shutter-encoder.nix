{inputs, ...}: {
  flake.nixosModules.shutterEncoder = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
    asset = inputs.sources.releaseAssets.shutterEncoder;
    uiscale = 2.0; # Adjust as needed for high-DPI displays

    src = pkgs.fetchurl {
      inherit (asset) url sha256 name;
    };

    # Centralized all file and directory paths, always quoted for safety
    shutterAppSrc = "usr/lib/Shutter Encoder";
    shutterAppDest = "$out/app";
    shutterIconSrc = "usr/lib/Shutter Encoder/usr/share/icons/hicolor/256x256/apps/icon.png";
    shutterIconDest = "$out/share/icons/hicolor/256x256/apps/shutter-encoder.png";
    shutterDesktopSrc = "usr/share/applications/Shutter_Encoder.desktop";
    shutterDesktopDest = "$out/share/applications/shutter-encoder.desktop";

    shutterData = pkgs.stdenv.mkDerivation {
      pname = "shutter-encoder-data";
      version = asset.version;

      inherit src;
      nativeBuildInputs = [pkgs.dpkg];

      unpackPhase = ''
        dpkg-deb -x $src .
      '';

      installPhase = ''
        mkdir -p "${shutterAppDest}"
        cp -r "${shutterAppSrc}"/* "${shutterAppDest}"

        mkdir -p "$(dirname "${shutterIconDest}")"
        cp "${shutterIconSrc}" "${shutterIconDest}"

        mkdir -p "$(dirname "${shutterDesktopDest}")"
        cp "${shutterDesktopSrc}" "${shutterDesktopDest}"
      '';
    };

    # FHS runtime
    shutterEncoder = pkgs.buildFHSEnv {
      name = "shutter-encoder";

      targetPkgs = pkgs:
        with pkgs; [
          ffmpeg
          jre
          gtk3
          glib
          gdk-pixbuf
          pango
          cairo
          atk
          fontconfig
          freetype
          libGL
          libX11
          libXext
          libXrender
          libXtst
          libXi
          alsa-lib
          zlib
          fuse
          xorg.xdpyinfo
        ];

      runScript = "${pkgs.writeShellScript "shutter-launch" ''
        # Inject the Java UI scale flag via environment variable
        export _JAVA_OPTIONS="-Dsun.java2d.uiScale=${toString uiscale}"

        APP="${shutterData}/app"
        cd "$APP"
        exec ./AppRun "$@"
      ''}";
    };
  in {
    home-manager.users.${username} = {...}: {
      home.packages = [shutterEncoder];

      # Fix desktop entry (point to correct binary)
      xdg.desktopEntries.shutter-encoder = {
        name = "Shutter Encoder";
        exec = "shutter-encoder";
        icon = "shutter-encoder";
        categories = ["AudioVideo" "Video"];
        type = "Application";
      };

      # Provide icon from store
      home.file.".local/share/icons/hicolor/256x256/apps/shutter-encoder.png".source = "${shutterData}/share/icons/hicolor/256x256/apps/shutter-encoder.png";
    };
  };
}
