{...}: {
  flake.nixosModules.services = {
    config,
    lib,
    ...
  }: let
    username = config.myConfig.primaryUser;
  in {
    services.power-profiles-daemon.enable = true;
    services.upower.enable = true;

    # Needed by Noctalia's KDE Connect plugin and opens required firewall ports.
    programs.kdeconnect.enable = true;

    home-manager.users.${username} = {
      # Ensure kdeconnectd runs in the user session on non-KDE desktops.
      services.kdeconnect.enable = true;

      # Start kdeconnectd automatically with the user systemd default target.
      # systemd.user.services.kdeconnect.Install.WantedBy =
      #   lib.mkAfter ["default.target"];
    };
  };
}
