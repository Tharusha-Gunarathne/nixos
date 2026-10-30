{...}: {
  flake.nixosModules.edge = {
    pkgs,
    config,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
    edgeArgs = [
      "--enable-features=TouchpadOverscrollHistoryNavigation,UseOzonePlatform"
      "--disable-features=WaylandLinuxDrmSyncobjKMS"
      "--ozone-platform=wayland"
    ];
    edgeFlags = lib.concatStringsSep " " edgeArgs;
    browserMimeHandlers = [
      "text/html"
      "x-scheme-handler/http"
      "x-scheme-handler/https"
      "x-scheme-handler/about"
      "x-scheme-handler/unknown"
    ];
    mkEdgeLauncher = name: profile:
      pkgs.writeShellScriptBin name ''
        exec ${pkgs.microsoft-edge}/bin/microsoft-edge \
          --profile-directory=${lib.escapeShellArg profile} \
          --no-first-run \
          --no-default-browser-check \
          ${edgeFlags} \
          "$@"
      '';
    edgeDefaultLauncher = mkEdgeLauncher "edge-default-launcher" "Default";
    edgeIncognitoLauncher = mkEdgeLauncher "edge-incognito-launcher" "Profile 3";
  in {
    home-manager.users.${username} = {...}: {
      home.packages = [
        edgeDefaultLauncher
        edgeIncognitoLauncher
      ];

      xdg.mimeApps.defaultApplications = builtins.listToAttrs (
        map (mime: {
          name = mime;
          value = ["microsoft-edge.desktop"];
        })
        browserMimeHandlers
      );

      # Same id as the package's entry, so this one shadows it.
      xdg.desktopEntries.microsoft-edge = {
        name = "Microsoft Edge";
        genericName = "Web Browser";
        comment = "Browse the Web";
        exec = "${edgeDefaultLauncher}/bin/edge-default-launcher %U";
        icon = "microsoft-edge";
        categories = ["Network" "WebBrowser"];
        mimeType = browserMimeHandlers ++ ["application/xhtml+xml" "application/pdf"];
        settings.StartupWMClass = "microsoft-edge";
        terminal = false;
      };

      xdg.desktopEntries.edge-incognito = {
        name = "Microsoft Edge | Incognito";
        genericName = "Web Browser";
        comment = "Open Edge using the incognito profile";
        exec = "${edgeIncognitoLauncher}/bin/edge-incognito-launcher %U";
        icon = "microsoft-edge";
        categories = ["Network" "WebBrowser"];
        terminal = false;
      };

      # The package also ships a duplicate com.microsoft.Edge entry.
      xdg.desktopEntries."com.microsoft.Edge" = {
        name = "Microsoft Edge";
        exec = "${edgeDefaultLauncher}/bin/edge-default-launcher %U";
        noDisplay = true;
      };
    };

    environment.etc."opt/edge/policies/managed/extensions.json".text = builtins.toJSON {
      ExtensionInstallForcelist = map (id: "${id};https://clients2.google.com/service/update2/crx") [
        "ddkjiahejlhfcafbddmgiahcphecmpfh" # uBlock Origin Lite
        "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
        "ghbmnnjooekpmoecnnnilnnbdlolhkhiz" # Google Docs
        "kcmipingpfbohfjckomimmahknoddnke" # Vicinae Integration
      ];
    };
  };
}
