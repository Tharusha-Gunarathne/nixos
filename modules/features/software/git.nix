{localConfig, ...}: {
  flake.nixosModules.git = {config, ...}: let
    username = config.myConfig.primaryUser;
  in {
    home-manager.users.${username} = {...}: {
      programs.git = {
        enable = true;
        settings.user = {
          name = localConfig.user.git_name;
          email = localConfig.user.git_email;
        };
      };
    };
  };
}
