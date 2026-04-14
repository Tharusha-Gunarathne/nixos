{inputs, ...}: {
  flake.nixosModules.xdm = {
    pkgs,
    config,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
    xdmAsset = inputs.sources.releaseAssets.xdm;

    xdmanScript = pkgs.writeShellScript "xdman" ''
      pkill -f xdm-app 2>/dev/null
      sleep 0.5
      cd @out@/opt/xdman
      exec @out@/opt/xdman/xdm-app "$@"
    '';

    xdm = pkgs.stdenv.mkDerivation {
      pname = "xdm";
      version = xdmAsset.version;

      src = pkgs.fetchurl {
        inherit (xdmAsset) url sha256;
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

        sed -i "s|^Exec=.*|Exec=$out/bin/xdman %U|" \
          $out/share/applications/xdm-app.desktop

        sed -i "s|^Icon=.*|Icon=$out/share/icons/hicolor/scalable/apps/xdm-app.svg|" \
          $out/share/applications/xdm-app.desktop

        sed -i "s|^MimeType=.*|MimeType=application/xdm-app;x-scheme-handler/xdm-app;x-scheme-handler/xdm+app;|" \
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
    }: let
      chromiumExtensionPath = "${config.home.homeDirectory}/.local/share/xdm";
    in {
      home.packages = [xdm];

      # Autostart Configuration for XDM
      # Uncomment to enable autostart on activation
      # xdg.configFile."autostart/xdm-app.desktop" = {
      #   source = "${xdm}/share/applications/xdm-app.desktop";
      #   force = true;
      # };

      # Remove XDM autostart entries so it never starts without a proper Wayland session
      home.activation.removeXdmAutostart = lib.hm.dag.entryAfter ["writeBoundary"] ''
        rm -f "${config.home.homeDirectory}/.config/autostart/xdm-app.desktop"
        rm -f "${config.home.homeDirectory}/.config/autostart/xdman.desktop"
      '';

      # Stable symlink for Chromium-based browser extension — load unpacked once,
      # survives all rebuilds automatically
      home.activation.xdmExtensionLink = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${chromiumExtensionPath}"
        ln -sfn "${xdm}/opt/xdman/chrome-extension" \
          "${chromiumExtensionPath}/chrome-extension"
      '';

      # Register xdm+app:// URI scheme handler so the browser extension
      # can launch XDM when clicking download links
      home.activation.xdmSchemeHandler = lib.hm.dag.entryAfter ["writeBoundary"] ''
        ${pkgs.xdg-utils}/bin/xdg-mime default xdm-app.desktop x-scheme-handler/xdm+app
      '';
    };
  };
}
