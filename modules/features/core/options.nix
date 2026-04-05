{...}: {
  flake.nixosModules.options = {
    lib,
    config,
    ...
  }: {
    options.myConfig = {
      username = lib.mkOption {
        type = lib.types.str;
        description = "Primary user account name";
      };
      repoRoot = lib.mkOption {
        type = lib.types.str;
        description = "Absolute path to the nixos-configs repo root";
        default = "/home/${config.myConfig.username}/nixos-configs";
      };
    };
  };
}
