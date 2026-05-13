{...}: {
  flake.nixosModules.kitty = {config, ...}: let
    username = config.myConfig.primaryUser;
  in {
    home-manager.users.${username} = {
      pkgs,
      ...
    }: {
      programs.kitty = {
        enable = true;
        font.name = "JetBrainsMono Nerd Font";
        font.size = 11;
        settings = {
          window_padding_width = 12;
          confirm_os_window_close = 0;
          shell = "${pkgs.fish}/bin/fish";
          cursor_trail = 1;
          allow_remote_control = "socket-only";
        };
      };
    };
  };
}