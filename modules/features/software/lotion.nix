{inputs, ...}: {
  flake.nixosModules.lotion = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
    lotionAsset = inputs.sources.releaseAssets.lotion;

    # Centralized file and directory paths for easier maintenance
    lotionLibDir = "usr/lib/lotion";
    lotionOutLibDir = "$out/lib/lotion";
    lotionDesktopSrc = "usr/share/applications/lotion.desktop";
    lotionDesktopDest = "$out/share/applications/lotion.desktop";
    lotionIconSrc = "usr/share/pixmaps/lotion.png";
    lotionIconDest = "$out/share/pixmaps/lotion.png";
    lotionBin = "$out/bin/lotion";
    lotionWrappedBin = "$out/lib/lotion/lotion";
    lotionIconPath = "$out/share/pixmaps/lotion.png";

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

        # Copy main application
        cp -r ${lotionLibDir} ${lotionOutLibDir}

        # Copy desktop file and icon
        cp ${lotionDesktopSrc} ${lotionDesktopDest}
        cp ${lotionIconSrc} ${lotionIconDest}

        # Fix the Icon path
        substituteInPlace ${lotionDesktopDest} \
          --replace "Icon=lotion" "Icon=${lotionIconPath}"

        # Fix the Exec path to point to the Nix store binary
        # (This replaces whatever Exec=... is currently there with the correct one)
        sed -i "s|^Exec=.*|Exec=${lotionBin} %U|" \
          ${lotionDesktopDest}

        # Wrap the binary with Wayland flags AND the sandbox fix
        makeWrapper ${lotionWrappedBin} ${lotionBin} \
          --add-flags "--no-sandbox" \
          --add-flags "--ozone-platform-hint=auto" \
          --add-flags "--enable-wayland-ime" \
          --add-flags "--enable-features=WaylandWindowDecorations"
      '';
    };
  in {
    home-manager.users.${username} = {...}: {
      home.packages = [lotion];
    };
  };
}
