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
      shell = lib.mkOption {
        type = lib.types.submodule {
          options = {
            noctalia = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable Noctalia shell integrations.";
            };
          };
        };
        description = "Feature flags for shell-specific integrations.";
        default = {};
      };
    };
  };
}
