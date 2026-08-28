{...}: {
  flake.nixosModules.kdeconnect = {
    config,
    lib,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    bridge = pkgs.kdeconnect-portal-fix;
  in {
    # Opens required firewall ports and installs the kdeconnect package.
    programs.kdeconnect.enable = true;

    # Route only the RemoteDesktop interface to the bridge under niri.
    # Everything else (screencast, notifications, secrets, etc.) keeps
    # using whatever's already configured (niri-flake / flatpak.nix).
    xdg.portal.config.niri."org.freedesktop.impl.portal.RemoteDesktop" =
      lib.mkForce ["hypr-kdeconnect"];

    home-manager.users.${username} = {...}: {
      # Ensures kdeconnectd runs in the user session on non-KDE desktops.
      services.kdeconnect.enable = true;

      # RemoteDesktop portal bridge — makes remote input work under niri.
      home.packages = [bridge];

      xdg.dataFile."xdg-desktop-portal/portals/hypr-kdeconnect.portal".source = "${bridge}/share/xdg-desktop-portal/portals/hypr-kdeconnect.portal";

      xdg.dataFile."dbus-1/services/org.freedesktop.impl.portal.desktop.hypr_kdeconnect.service".source = "${bridge}/share/dbus-1/services/org.freedesktop.impl.portal.desktop.hypr_kdeconnect.service";

      systemd.user.services.hypr-kdeconnect-portal = {
        Unit = {
          Description = "KDE Connect RemoteDesktop portal bridge";
          After = ["graphical-session.target"];
          PartOf = ["graphical-session.target"];
        };
        Service = {
          ExecStart = "${bridge}/bin/hypr-kdeconnect-portal";
          Restart = "on-failure";
          RestartSec = 2;
        };
        Install.WantedBy = ["graphical-session.target"];
      };
    };
  };
}
