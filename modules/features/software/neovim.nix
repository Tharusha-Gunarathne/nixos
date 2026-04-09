{...}: {
  flake.nixosModules.neovim = {config, ...}: let
    username = config.myConfig.username;
  in {
    home-manager.users.${username} = {...}: {
      programs.neovim = {
        enable = true;
        defaultEditor = true;
        withRuby = true;
        withPython3 = true;
        extraConfig = "set number relativenumber";
      };

      xdg.desktopEntries.nvim = {
        name = "Neovim wrapper";
        genericName = "Text Editor";
        icon = "nvim";
        exec = "kitty -e nvim %F";
        terminal = false;
        categories = ["Utility" "TextEditor"];
        mimeType = ["text/plain"];
      };
    };
  };
}
