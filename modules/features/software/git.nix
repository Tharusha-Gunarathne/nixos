{ self, ... }: {
  flake.homeManagerModules.git = { ... }: {
    programs.git = {
      enable = true;
      settings.user = {
        name = "Tharush2002";
        email = "172119123+Tharusha-Gunarathne@users.noreply.github.com";
      };
    };
  };
}
