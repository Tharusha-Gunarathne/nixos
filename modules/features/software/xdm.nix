{inputs, ...}: {
  flake.nixosModules.xdm = {
    pkgs,
    config,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
    xdmAsset = inputs.sources.releaseAssets.xdm;

    # Centralized file and directory paths for easier maintenance
    xdmOptDir = "opt/xdman";
    xdmOutOptDir = "$out/opt/xdman";
    xdmLogoSvgSrc = "opt/xdman/xdm-logo.svg";
    xdmLogoSvgDest = "$out/share/icons/hicolor/scalable/apps/xdm-app.svg";
    xdmLogoPngSrc = "opt/xdman/xdm-logo-512.png";
    xdmLogoPngDest = "$out/share/pixmaps/xdm.png";
    xdmDesktopSrc = "opt/xdman/xdm-app.desktop";
    xdmDesktopDest = "$out/share/applications/xdm-app.desktop";
    xdmBin = "$out/bin/xdman";
    xdmIconPath = "$out/share/icons/hicolor/scalable/apps/xdm-app.svg";
    xdmMimeType = "MimeType=application/xdm-app;x-scheme-handler/xdm-app;x-scheme-handler/xdm+app;";

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

        mkdir -p ${xdmOutOptDir} $out/bin $out/share/applications $out/share/pixmaps
        mkdir -p $out/share/icons/hicolor/scalable/apps

        cp -r ${xdmOptDir}/. ${xdmOutOptDir}/

        cp ${xdmLogoSvgSrc} ${xdmLogoSvgDest}
        cp ${xdmLogoPngSrc} ${xdmLogoPngDest}

        cp ${xdmDesktopSrc} ${xdmDesktopDest}

        sed -i "s|^Exec=.*|Exec=${xdmBin} %U|" \
          ${xdmDesktopDest}

        sed -i "s|^Icon=.*|Icon=${xdmIconPath}|" \
          ${xdmDesktopDest}

        sed -i "s|^MimeType=.*|${xdmMimeType}|" \
          ${xdmDesktopDest}

        sed "s|@out@|$out|g" ${xdmanScript} > ${xdmBin}
        chmod +x ${xdmBin}

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
      xdg.mimeApps = {
        enable = true;
        defaultApplications = {
          "x-scheme-handler/xdm+app" = "xdm-app.desktop";
          "x-scheme-handler/xdm-app" = "xdm-app.desktop";
          "application/xdm-app" = "xdm-app.desktop";
        };
      };
    };
  };
}
