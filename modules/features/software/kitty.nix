{ self, ... }: {
  flake.nixosModules.kitty = { config, ... }:
  let
    username = config.myConfig.username;
  in {
    home-manager.users.${username} = { pkgs, lib, config, ... }: {

      #  Add placeholder noctalia color scheme settings
      home.activation.kittyNoctaliaTheme = lib.hm.dag.entryAfter ["writeBoundary"] ''
        mkdir -p "${config.xdg.configHome}/kitty/themes"
        if [ ! -f "${config.xdg.configHome}/kitty/themes/noctalia.conf" ]; then
          touch "${config.xdg.configHome}/kitty/themes/noctalia.conf"
        fi
      '';

      programs.kitty = {
        enable = true;
        font.name = "JetBrainsMono Nerd Font";
        font.size = 11;
        extraConfig = "include themes/noctalia.conf";
        settings = {
          window_padding_width = 12;
          confirm_os_window_close = 0;
          shell = "${pkgs.fish}/bin/fish"; # launch fish in kitty
          cursor_trail = 1;
        };
      };
    };
  };
}
