{localConfig, ...}: {
  flake.nixosModules.desktopEntries = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    private_appServerLocation = localConfig.paths.private_app_server_dir;
    private_appServerLauncher = pkgs.writeShellScriptBin "private_app-server-desktop" ''
      cd ${private_appServerLocation}
      exec ./private_app-linux
    '';
  in {
    home-manager.users.${username} = {...}: {
      xdg.desktopEntries = {
        private_app-Server-Desktop = {
          name = "private_app Server - Desktop";
          genericName = "private_app Server";
          comment = "Run private_app Server in desktop";
          exec = ''kitty --title "private_app Server" ${private_appServerLauncher}/bin/private_app-server-desktop'';
          icon = "${private_appServerLocation}/icon.png";
          categories = ["Development"];
          terminal = false;
        };
      };
    };
  };
}
