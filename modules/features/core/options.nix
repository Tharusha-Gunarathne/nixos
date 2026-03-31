{ self, ... }: {
  flake.nixosModules.options = { lib, ... }: {
    options.myConfig = {
      username = lib.mkOption {
        type = lib.types.str;
        description = "Primary user account name";
      };
    };
  };
}
