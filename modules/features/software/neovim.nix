{ self, ... }: {
  flake.nixosModules.neovim = { config, ... }:
  let
    username = config.myConfig.username;
  in {
    home-manager.users.${username} = { ... }: {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        extraConfig = "set number relativenumber";
      };
    };
  };
}
