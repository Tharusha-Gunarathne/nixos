{self, ...}: {
  flake.nixosModules.xdm = {
    pkgs,
    config,
    lib,
    ...
  }: let
    chromiumExtensionPath = "${config.home.homeDirectory}/.local/share/xdm";
    username = config.myConfig.username;

    xdmanScript = pkgs.writeShellScript "xdman" ''
      pkill -f xdm-app 2>/dev/null
      sleep 0.5
      cd @out@/opt/xdman
      exec @out@/opt/xdman/xdm-app "$@"
    '';

    xdm = pkgs.stdenv.mkDerivation rec {
      pname = "xdm";
      version = "8.0.29";

      src = pkgs.fetchurl {
        url = "https://github.com/subhra74/xdm/releases/download/${version}/xdman_gtk_${version}_amd64.deb";
        sha256 = "04cydd5i94qbnsi2535mswapng6hbwc567jhzbq8s715n0nvnn9n";
      };

      nativeBuildInputs = with pkgs; [
        autoPatchelfHook
        wrapGAppsHook3
      ];

      buildInputs = with pkgs; [
        gtk3
        glib
        gdk-pixbuf
        librsvg
        pango
        cairo
        atk
        libGL
        openssl
        zlib
        icu
      ];

      unpackPhase = ''
        ar x $src
        tar xf data.tar.xz
      '';

      dontConfigure = true;
      dontBuild = true;
      dontWrapGApps = false;
      autoPatchelfIgnoreMissingDeps = ["liblttng-ust.so.0"];

      installPhase = ''
        runHook preInstall

        mkdir -p $out/opt/xdman $out/bin $out/share/applications $out/share/pixmaps
        mkdir -p $out/share/icons/hicolor/scalable/apps

        cp -r opt/xdman/. $out/opt/xdman/

        cp opt/xdman/xdm-logo.svg $out/share/icons/hicolor/scalable/apps/xdm-app.svg
        cp opt/xdman/xdm-logo-512.png $out/share/pixmaps/xdm.png

        cp opt/xdman/xdm-app.desktop $out/share/applications/

        # Use sed regex to replace the ENTIRE Exec line — no fragile string matching
        sed -i "s|^Exec=.*|Exec=$out/bin/xdman %U|" \
          $out/share/applications/xdm-app.desktop

        # Fix icon
        sed -i "s|^Icon=.*|Icon=$out/share/icons/hicolor/scalable/apps/xdm-app.svg|" \
          $out/share/applications/xdm-app.desktop

        sed "s|@out@|$out|g" ${xdmanScript} > $out/bin/xdman
        chmod +x $out/bin/xdman

        runHook postInstall
      '';

      preFixup = ''
        gappsWrapperArgs+=(
          --chdir "$out/opt/xdman"
          --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath (with pkgs; [
          gtk3
          glib
          gdk-pixbuf
          librsvg
          pango
          cairo
          atk
          libGL
          openssl
          zlib
          icu
        ])}
        )
      '';

      meta = with lib; {
        description = "Xtreme Download Manager — accelerates downloads up to 500%";
        homepage = "https://xtremedownloadmanager.com";
        license = licenses.lgpl21Only;
        platforms = ["x86_64-linux"];
        mainProgram = "xdman";
      };
    };
  in {
    home-manager.users.${username} = {
      config,
      lib,
      ...
    }: {
      home.packages = [xdm];
      # Autostart Configuration for XDM
      # Home-manager owns the autostart file so XDM can never
      # overwrite it with a raw-binary path at runtime
      # Uncomment to enable autostart on activation
      # xdg.configFile."autostart/xdm-app.desktop" = {
      #   source = "${xdm}/share/applications/xdm-app.desktop";
      #   force = true;
      # };

      # Remove XDM autostart entries on deactivation
      # Comment to reenable autostart on reactivation
      home.activation.removeXdmAutostart = lib.hm.dag.entryAfter ["writeBoundary"] ''
        rm -f "${config.home.homeDirectory}/.config/autostart/xdm-app.desktop"
        rm -f "${config.home.homeDirectory}/.config/autostart/xdman.desktop"
      '';

      # XDM Browser Extension Configuration - CHROMIUM-BASED BROWSERS
      home.activation.xdmExtensionLink = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${chromiumExtensionPath}"
        ln -sfn "${xdm}/opt/xdman/chrome-extension" \
          "${chromiumExtensionPath}/chrome-extension"
      '';
    };
  };
}
