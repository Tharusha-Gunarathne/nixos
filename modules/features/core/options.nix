{...}: {
  flake.nixosModules.options = {
    lib,
    config,
    ...
  }: {
    options.myConfig = {
      primaryUser = lib.mkOption {
        type = lib.types.str;
        default = "tharusha-gunarathne";
        description = "Primary user account name";
      };
      primaryUid = lib.mkOption {
        type = lib.types.int;
        default = 1000;
        description = "UID of the primary user account";
      };
      repoRoot = lib.mkOption {
        type = lib.types.str;
        description = "Absolute path to the nixos-configs repo root";
        default = "/home/${config.myConfig.primaryUser}/nixos-configs";
      };
      storage = lib.mkOption {
        type = lib.types.submodule {
          options = {
            rootUuid = lib.mkOption {
              type = lib.types.str;
              default = "00000000-0000-0000-0000-000000000000";
              description = "Root filesystem UUID.";
            };
            bootUuid = lib.mkOption {
              type = lib.types.str;
              default = "6A90-3D23";
              description = "Boot filesystem UUID.";
            };
            dataDrives = lib.mkOption {
              type = lib.types.listOf (lib.types.submodule {
                options = {
                  name = lib.mkOption {
                    type = lib.types.str;
                    description = "Mount name under /mnt.";
                  };
                  uuid = lib.mkOption {
                    type = lib.types.str;
                    description = "Drive UUID for /dev/disk/by-uuid.";
                  };
                };
              });
              default = [
                {
                  name = "D_Drive";
                  uuid = "01DCC7D0F4666AF0";
                }
                {
                  name = "E_Drive";
                  uuid = "ACAE0ACAAE0A8D50";
                }
              ];
              description = "Additional data drives mounted under /mnt.";
            };
          };
        };
        default = {};
        description = "System-specific storage identifiers and mounts.";
      };
      shell = lib.mkOption {
        type = lib.types.submodule {
          options = {
            noctalia = lib.mkOption {
              type = lib.types.bool;
              default = true;
              description = "Enable Noctalia shell integrations.";
            };
            # Add more shell-specific feature flags here as needed.
            # shell = lib.mkOption {
            #   type = lib.types.bool;
            #   default = false;
            #   description = "Enable features specific to <shell>.";
            # };
          };
        };
        description = "Feature flags for shell-specific integrations.";
        default = {};
      };
    };
  };
}
