{inputs, ...}: {
  flake.nixosModules.lotion = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
    lotionAsset = inputs.sources.releaseAssets.lotion;

    lotion = pkgs.stdenv.mkDerivation {
      pname = "lotion";
      version = lotionAsset.version;

      src = pkgs.fetchurl {
        inherit (lotionAsset) url sha256;
      };

      nativeBuildInputs = [
        pkgs.dpkg
        pkgs.autoPatchelfHook
        pkgs.makeWrapper
      ];

      buildInputs = [
        pkgs.stdenv.cc.cc.lib
        pkgs.alsa-lib
        pkgs.libdrm
        pkgs.mesa
        pkgs.nss
        pkgs.nspr
        pkgs.atk
        pkgs.cups
        pkgs.expat
        pkgs.libxkbcommon
        pkgs.gtk3
        pkgs.pango
        pkgs.cairo
        pkgs.glib
        pkgs.dbus
        pkgs.libx11
        pkgs.libxcomposite
        pkgs.libxdamage
        pkgs.libxext
        pkgs.libxfixes
        pkgs.libxrandr
        pkgs.libxcb
      ];

      unpackPhase = ''
        dpkg-deb --fsys-tarfile $src | tar x --no-same-permissions --no-same-owner
      '';

      installPhase = ''
        mkdir -p $out/lib $out/bin
        mkdir -p $out/share/applications
        mkdir -p $out/share/pixmaps
        mkdir -p $out/share/icons/hicolor/256x256/apps
        mkdir -p $out/share/icons/hicolor/128x128/apps
        mkdir -p $out/share/icons/hicolor/48x48/apps

        cp -r usr/lib/lotion $out/lib/lotion
        cp usr/share/applications/lotion.desktop $out/share/applications/
        cp usr/share/pixmaps/lotion.png $out/share/pixmaps/
        cp usr/share/pixmaps/lotion.png $out/share/icons/hicolor/256x256/apps/lotion.png
        cp usr/share/pixmaps/lotion.png $out/share/icons/hicolor/128x128/apps/lotion.png
        cp usr/share/pixmaps/lotion.png $out/share/icons/hicolor/48x48/apps/lotion.png

        # Use absolute icon path so launcher doesn't need to resolve by name
        substituteInPlace $out/share/applications/lotion.desktop \
          --replace "Icon=lotion" "Icon=$out/share/pixmaps/lotion.png"

        makeWrapper $out/lib/lotion/lotion $out/bin/lotion \
          --add-flags "--no-sandbox"
      '';
    };
  in {
    home-manager.users.${username} = {...}: {
      home.packages = [lotion];
    };
  };
}
