{...}: {
  flake.nixosModules.kdeconnect = {
    config,
    ...
  }: let
    username = config.myConfig.primaryUser;
  in {
    # Opens required firewall ports and installs the kdeconnect package.
    programs.kdeconnect.enable = true;

    home-manager.users.${username} = {
      # Ensures kdeconnectd runs in the user session on non-KDE desktops.
      services.kdeconnect.enable = true;
    };
  };
}