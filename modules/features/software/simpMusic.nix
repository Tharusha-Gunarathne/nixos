{inputs, ...}: {
  flake.nixosModules.simpMusic = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    asset = inputs.sources.releaseAssets.simpMusic;

    appimageContents = pkgs.appimageTools.extractType2 {
      pname = "simpmusic";
      version = asset.version;
      src = pkgs.fetchurl {
        inherit (asset) url sha256 name;
      };
    };

    simpMusic = pkgs.appimageTools.wrapType2 {
      pname = "simpmusic";
      version = asset.version;

      src = pkgs.fetchurl {
        inherit (asset) url sha256 name;
      };

      extraInstallCommands = ''
        mkdir -p $out/share/icons/hicolor/256x256/apps
        mkdir -p $out/share/applications

        # Remove AppImage's own desktop entry to avoid duplicates
        rm -f $out/share/applications/*.desktop

        # Copy icon from extracted AppImage contents
        if [ -f "${appimageContents}/simpmusic.png" ]; then
          cp "${appimageContents}/simpmusic.png" $out/share/icons/hicolor/256x256/apps/simpmusic.png
        elif [ -f "${appimageContents}/SimpMusic.png" ]; then
          cp "${appimageContents}/SimpMusic.png" $out/share/icons/hicolor/256x256/apps/simpmusic.png
        else
          find ${appimageContents} -name "*.png" | head -1 | xargs -I{} cp {} $out/share/icons/hicolor/256x256/apps/simpmusic.png || true
        fi

        # Custom desktop entry with correct WMClass, scaling, and runtime paths
        cat > $out/share/applications/simpmusic.desktop << EOF
        [Desktop Entry]
        Type=Application
        Name=SimpMusic
        GenericName=Music Player
        Comment=YouTube Music client
        Exec=env _JAVA_OPTIONS="-Dsun.java2d.uiScale=2.0" VLC_PLUGIN_PATH=/home/${username}/.local/share/simpmusic-vlc-plugins YT_DLP_PATH=/run/current-system/sw/bin/yt-dlp simpmusic %U
        Icon=simpmusic
        Categories=Audio;Music;Player;AudioVideo;
        MimeType=x-scheme-handler/simpmusic;
        StartupWMClass=com-maxrave-simpmusic-MainKt
        Terminal=false
        EOF
      '';
    };
  in {
    environment.systemPackages = with pkgs; [
      yt-dlp
      vlc
    ];

    home-manager.users.${username} = {lib, ...}: {
      home.packages = [simpMusic];

      home.activation.simpMusicSetup = lib.hm.dag.entryAfter ["writeBoundary"] ''
        # Block AppImage from auto-registering its own desktop entry
        BLOCKED="$HOME/.local/share/applications/com-maxrave-simpmusic-MainKt.desktop"
        mkdir -p "$(dirname "$BLOCKED")"
        rm -f "$BLOCKED"
        touch "$BLOCKED"
        chmod 444 "$BLOCKED"
      
        # Copy icon into user icon cache so launchers can find it
        ICON_SRC="${simpMusic}/share/icons/hicolor/256x256/apps/simpmusic.png"
        ICON_DEST="$HOME/.local/share/icons/hicolor/256x256/apps/simpmusic.png"
        mkdir -p "$(dirname "$ICON_DEST")"
        if [ -f "$ICON_SRC" ]; then
          ${pkgs.coreutils}/bin/cp -f "$ICON_SRC" "$ICON_DEST"
          ${pkgs.gtk3}/bin/gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
        fi
      
        # Copy system VLC plugins so SimpMusic can play WebM/Opus audio from YouTube
        VLC_DEST="$HOME/.local/share/simpmusic-vlc-plugins"
        # Make writable before removing so rebuild doesn't fail
        chmod -R u+w "$VLC_DEST" 2>/dev/null || true
        rm -rf "$VLC_DEST"
        mkdir -p "$VLC_DEST"
        ${pkgs.coreutils}/bin/cp -r ${pkgs.vlc}/lib/vlc/plugins/. "$VLC_DEST/"
        # Make writable so future rebuilds can clean it up
        chmod -R u+w "$VLC_DEST"
      '';

      home.sessionVariables = {
        _JAVA_OPTIONS = "-Dsun.java2d.uiScale=2.0";
        SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        NIX_SSL_CERT_FILE = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
        YT_DLP_PATH = "/run/current-system/sw/bin/yt-dlp";
        VLC_PLUGIN_PATH = "$HOME/.local/share/simpmusic-vlc-plugins";
      };
    };
  };
}
