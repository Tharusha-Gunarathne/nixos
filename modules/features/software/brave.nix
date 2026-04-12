{...}: {
  flake.nixosModules.brave = {
    pkgs,
    config,
    lib,
    ...
  }: let
    username = config.myConfig.username;
  in {
    environment.etc."brave-flags.conf".text = ''
      --enable-features=TouchpadOverscrollHistoryNavigation,UseOzonePlatform
      --ozone-platform=wayland
    '';

    home-manager.users.${username} = {
      lib,
      ...
    }: {
      programs.chromium = {
        enable = true;
        package = pkgs.brave;
        commandLineArgs = [
          "--enable-features=TouchpadOverscrollHistoryNavigation,UseOzonePlatform"
          "--ozone-platform=wayland"
        ];
      };

      home.activation.braveDesktopExecFlags = lib.hm.dag.entryAfter ["writeBoundary"] ''
        SRC="${pkgs.brave}/share/applications/brave-browser.desktop"
        DST="$HOME/.local/share/applications/brave-browser.desktop"
        FLAGS=' --enable-features=TouchpadOverscrollHistoryNavigation,UseOzonePlatform --ozone-platform=wayland'

        mkdir -p "$HOME/.local/share/applications"

        ${pkgs.gawk}/bin/awk -v flags="$FLAGS" '
          BEGIN { OFS = "" }
          /^Exec=/ {
            cmd = substr($0, 6)
            if (cmd !~ /TouchpadOverscrollHistoryNavigation/) {
              if (cmd ~ / %U$/) {
                sub(/ %U$/, flags " %U", cmd)
              } else {
                cmd = cmd flags
              }
            }
            print "Exec=", cmd
            next
          }
          { print }
        ' "$SRC" > "$DST"

        ${pkgs.desktop-file-utils}/bin/update-desktop-database "$HOME/.local/share/applications" >/dev/null 2>&1 || true
      '';
    };

    environment.etc."brave/policies/managed/extensions.json".text = builtins.toJSON {
      ExtensionInstallForcelist = [
        "ddkjiahejlhfcafbddmgiahcphecmpfh" # uBlock Origin Lite
        "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
      ];
    };
  };
}
