{self, ...}: {
  flake.nixosModules.vicinae = {config, ...}: let
    username = config.myConfig.username;
  in {
    home-manager.users.${username} = {...}: {
      programs.vicinae.enable = true;
    };
  };
}
