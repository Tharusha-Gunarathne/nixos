{...}: {
  flake.nixosModules.brave = {
    pkgs,
    config,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
    braveArgs = [
      "--enable-features=TouchpadOverscrollHistoryNavigation,UseOzonePlatform"
      "--disable-features=WaylandLinuxDrmSyncobjKMS"
      "--ozone-platform=wayland"
    ];
    braveFlags = lib.concatStringsSep " " braveArgs;
    browserMimeHandlers = [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "x-scheme-handler/about"
      "x-scheme-handler/unknown"
    ];
    braveDefaultLauncher = pkgs.writeShellScriptBin "brave-default-launcher" ''
      exec ${pkgs.brave}/bin/brave \
        --user-data-dir="$HOME/.config/BraveSoftware/Brave-Browser" \
        --profile-directory="Default" \
        --no-first-run \
        --no-default-browser-check \
        ${braveFlags} \
        "$@"
    '';
  in {
    environment.etc."brave-flags.conf".text =
      (lib.concatStringsSep "\n" braveArgs) + "\n";

    home-manager.users.${username} = {lib, ...}: {
      home.packages = [
        braveDefaultLauncher
      ];

      programs.chromium = {
        enable = true;
        package = pkgs.brave;
        commandLineArgs = braveArgs;
      };

      xdg.mimeApps.defaultApplications = builtins.listToAttrs (
        map (mime: {
          name = mime;
          value = ["brave-browser.desktop"];
        })
        browserMimeHandlers
      );

      xdg.desktopEntries.brave-profile-1 = {
        name = "Brave Web Browser | Incognito";
        genericName = "Web Browser";
        comment = "Open Brave using Profile 1";
        exec = "${pkgs.brave}/bin/brave --profile-directory=\"Profile 1\" ${braveFlags} %U";
        icon = "brave-browser";
        categories = ["Network" "WebBrowser"];
        terminal = false;
      };

      home.activation.braveDesktopCleanupAndDefaults = lib.hm.dag.entryAfter ["writeBoundary"] ''
        APPS_DIR="$HOME/.local/share/applications"
        MAIN_DESKTOP="$APPS_DIR/brave-browser.desktop"

        mkdir -p "$APPS_DIR"

        cat > "$MAIN_DESKTOP" <<'EOF'
        [Desktop Entry]
        Version=1.0
        Type=Application
        Name=Brave Web Browser
        GenericName=Web Browser
        Comment=Browse the Web
        Exec=${braveDefaultLauncher}/bin/brave-default-launcher %U
        Terminal=false
        Icon=brave-browser
        Categories=Network;WebBrowser;
        MimeType=application/pdf;application/rdf+xml;application/rss+xml;application/xhtml+xml;application/xhtml_xml;application/xml;text/html;text/xml;x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/chromium;x-scheme-handler/about;x-scheme-handler/unknown;
        x-scheme-handler/http;x-scheme-handler/https;x-scheme-handler/chromium;x-scheme-handler/about;x-scheme-handler/unknown;
        StartupWMClass=brave-browser
        EOF

        # Keep only the two managed Brave launchers: main and profile-1.
        if [ -d "$APPS_DIR" ]; then
          ${pkgs.findutils}/bin/find "$APPS_DIR" -maxdepth 1 -type f -name 'brave-*.desktop' \
          ! -name 'brave-browser.desktop' \
          ! -name 'brave-profile-1.desktop' \
          ! -name 'brave-*-Default.desktop' \
          ! -name 'brave-*-Profile_*.desktop' \
          -delete
        fi

        ${pkgs.xdg-utils}/bin/xdg-settings set default-web-browser brave-browser.desktop >/dev/null 2>&1 || true
        ${pkgs.xdg-utils}/bin/xdg-mime default brave-browser.desktop x-scheme-handler/http >/dev/null 2>&1 || true
        ${pkgs.xdg-utils}/bin/xdg-mime default brave-browser.desktop x-scheme-handler/https >/dev/null 2>&1 || true
        ${pkgs.xdg-utils}/bin/xdg-mime default brave-browser.desktop text/html >/dev/null 2>&1 || true

        ${pkgs.desktop-file-utils}/bin/update-desktop-database "$APPS_DIR" >/dev/null 2>&1 || true
      '';
    };

    environment.etc."brave/policies/managed/extensions.json".text = builtins.toJSON {
      ExtensionInstallForcelist = [
        "ddkjiahejlhfcafbddmgiahcphecmpfh" # uBlock Origin Lite
        "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
        "mhpeahbikehnfkfnmopaigggliclhmnc" # BroTab
      ];
    };
  };
}
