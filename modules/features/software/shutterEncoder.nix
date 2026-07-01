{inputs, ...}: {
  flake.nixosModules.shutterEncoder = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    asset = inputs.sources.releaseAssets.shutterEncoder;
    uiscale = 1.0;

    src = pkgs.fetchurl {
      inherit (asset) url sha256 name;
    };

    # 20.2 structure: everything under opt/shutter-encoder/
    shutterAppSrc    = "opt/shutter-encoder/lib/app";
    shutterAppDest   = "$out/app";
    shutterIconSrc   = "opt/shutter-encoder/lib/Shutter_Encoder.png";
    shutterIconDest  = "$out/share/icons/hicolor/256x256/apps/shutter-encoder.png";
    shutterDesktopSrc  = "opt/shutter-encoder/lib/shutter-encoder-Shutter_Encoder.desktop";
    shutterDesktopDest = "$out/share/applications/shutter-encoder.desktop";
    shutterBinSrc    = "opt/shutter-encoder/bin/Shutter Encoder";

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

        mkdir -p "$out/bin"
        cp "${shutterBinSrc}" "$out/bin/shutter-encoder-bin"
        chmod +x "$out/bin/shutter-encoder-bin"
      '';
    };

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
          xdpyinfo
        ];

      # 20.2 uses the binary directly instead of AppRun
      runScript = "${pkgs.writeShellScript "shutter-launch" ''
        export _JAVA_OPTIONS="-Dsun.java2d.uiScale=${toString uiscale}"
        exec "${shutterData}/bin/shutter-encoder-bin" "$@"
      ''}";
    };
  in {
    home-manager.users.${username} = {...}: {
      home.packages = [shutterEncoder];

      xdg.desktopEntries.shutter-encoder = {
        name = "Shutter Encoder";
        exec = "shutter-encoder";
        icon = "shutter-encoder";
        categories = ["AudioVideo" "Video"];
        type = "Application";
      };

      home.file.".local/share/icons/hicolor/256x256/apps/shutter-encoder.png".source =
        "${shutterData}/share/icons/hicolor/256x256/apps/shutter-encoder.png";
    };
  };
}