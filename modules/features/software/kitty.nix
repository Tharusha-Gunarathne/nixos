{ self, ... }: {
  flake.homeManagerModules.kitty = { ... }: {
    programs.kitty = {
      enable = true;
      font.name = "JetBrainsMono Nerd Font";
      font.size = 12;
      settings = {
        window_padding_width = 10;
        confirm_os_window_close = 0;
      };
    };
  };
}
