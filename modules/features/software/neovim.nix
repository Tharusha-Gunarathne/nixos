{ self, ... }: {
  flake.homeManagerModules.neovim = { ... }: {
    programs.neovim = {
      enable = true;
      defaultEditor = true;
      extraConfig = "set number relativenumber";
    };
  };
}
