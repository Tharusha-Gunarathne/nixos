{ self, ... }: {
  flake.homeManagerModules.vicinae = { ... }: {
    programs.vicinae = {
      enable = true;
    };
  };
}
