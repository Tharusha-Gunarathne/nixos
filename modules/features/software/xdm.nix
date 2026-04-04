{self, ...}: {
  flake.nixosModules.xdm = {
    config,
    pkgs,
    lib,
    ...
  }: let
    username = config.myConfig.username;

    xdm-pkg = pkgs.stdenv.mkDerivation rec {
      pname = "xdm";
      version = "7.2.11";

      src = pkgs.fetchurl {
        url = "https://github.com/subhra74/xdm/releases/download/${version}/xdm-setup-${version}.tar.xz";
        sha256 = "0f04c7f6j6ivfjynmlrbcp9lcvns532z18piql9ppncp2xji610l";
      };

      nativeBuildInputs = [
        pkgs.autoPatchelfHook
        pkgs.makeWrapper
      ];

      buildInputs = [
        pkgs.stdenv.cc.cc.lib
        pkgs.gtk3
        pkgs.glib
        pkgs.xorg.libX11
      ];

      # Disable phases that don't apply
      dontConfigure = true;
      dontBuild = true;

      unpackPhase = ''
        # The tarball is a self-extracting script; payload starts at block 2 (bs=8K skip=1)
        tar -xf $src install.sh
        dd if=install.sh bs=8K skip=1 | tar -xJf - 2>/dev/null
      '';

      installPhase = ''
        mkdir -p $out/lib $out/bin
        mkdir -p $out/share/applications
        mkdir -p $out/share/pixmaps
        mkdir -p $out/share/icons/hicolor/256x256/apps
        mkdir -p $out/share/icons/hicolor/48x48/apps

        # Copy the whole app directory (includes bundled JRE and jar)
        cp -r opt/xdman $out/lib/xdman

        # Copy icon
        cp $out/lib/xdman/icon.png $out/share/pixmaps/xdman.png
        cp $out/lib/xdman/icon.png $out/share/icons/hicolor/256x256/apps/xdman.png
        cp $out/lib/xdman/icon.png $out/share/icons/hicolor/48x48/apps/xdman.png

        # Copy desktop file and fix icon path
        cp usr/share/applications/xdman.desktop $out/share/applications/
        substituteInPlace $out/share/applications/xdman.desktop \
          --replace "Icon=xdman" "Icon=$out/share/pixmaps/xdman.png"

        # The bundled xdman launcher script references /opt/xdman — rewrite it
        makeWrapper $out/lib/xdman/jre/bin/java $out/bin/xdman \
          --add-flags "-jar $out/lib/xdman/xdman.jar" \
          --set XDG_CURRENT_DESKTOP gtk
      '';
    };
  in {
    home-manager.users.${username} = {...}: {
      home.packages = [xdm-pkg];
    };
  };
}