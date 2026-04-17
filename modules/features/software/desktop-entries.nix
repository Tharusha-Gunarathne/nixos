{...}: {
  flake.nixosModules.desktopEntries = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
  in {
    home-manager.users.${username} = {lib, ...}: {
      xdg.desktopEntries = {
        private_app-Server-Desktop = {
          name = "private_app Server - Desktop";
          genericName = "private_app Server";
          comment = "Run private_app Server in desktop";
          exec = "${pkgs.bash}/bin/bash -lc 'cd /mnt/E_Drive/_OTHER_/_SOFTWARES/Package_Changer/S/_private_app_DB_/private_app && exec ./private_app-linux'";
          icon = "utilities-terminal";
          categories = ["Utility" "Development"];
          terminal = true;
        };

        # my-custom-app-2 = {
        #   name = "Another Custom App";
        #   # ... etc
        # };
      };
    };
  };
}
