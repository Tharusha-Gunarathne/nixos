{localConfig, ...}: {
  flake.nixosModules.options = {
    lib,
    config,
    ...
  }: let
    lUser = localConfig.user;
    lRepoDir = lUser.repo_dir;
    lStorage = localConfig.storage;
  in {
    options.myConfig = {
      # User settings
      primaryUser = lib.mkOption {
        type = lib.types.str;
        default = lUser.username;
        description = "Primary user account name";
      };
      primaryUid = lib.mkOption {
        type = lib.types.int;
        default = lUser.uid;
        description = "UID of the primary user account";
      };

      # Predefined root directory for repo
      repoRoot = lib.mkOption {
        type = lib.types.str;
        description = "Absolute path to the nixos-configs repo root";
        default = "/home/${config.myConfig.primaryUser}/${lRepoDir}";
      };

      # Undervolt the CPU
      # To undervolt disable "Undervolt Protection" in the BIOS/UEFI, then find
      # stable undervolt values for your CPU and set them here.
      isUnderVoltEnabled = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable CPU undervolting. Requires Legion Optimization to be enabled & BIOS undervolt protection to be disabled.";
      };

      # Storage configuration for root, boot, and additional data drives
      storage = lib.mkOption {
        type = lib.types.submodule {
          options = {
            rootUuid = lib.mkOption {
              type = lib.types.str;
              default = lStorage.root_uuid;
              description = "Root filesystem UUID.";
            };
            bootUuid = lib.mkOption {
              type = lib.types.str;
              default = lStorage.boot_uuid;
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
              # Map TOML array-of-tables to the expected list format
              default = map (d: {inherit (d) name uuid;}) lStorage.data_drives;
              description = "Additional data drives mounted under /mnt.";
            };
          };
        };
        default = {};
        description = "System-specific storage identifiers and mounts.";
      };

      # Shell Configurations with multiple shell support
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
