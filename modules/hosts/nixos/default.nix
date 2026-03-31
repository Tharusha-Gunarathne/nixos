{ self, inputs, ... }: {
  flake.nixosConfigurations.nixos = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      self.nixosModules.nixosHardware
      self.nixosModules.nixosConfiguration
      inputs.home-manager.nixosModules.home-manager
      ({ config, ... }: {
        home-manager = {
          useGlobalPkgs = true;
          useUserPackages = true;
          backupFileExtension = "backup";
          sharedModules = [
            { _module.args.osConfig = self.nixosConfigurations.nixos.config; }
          ];
          users."${config.myConfig.username}" = { ... }: {
            imports = [
              self.homeManagerModules.git
              self.homeManagerModules.gtk
              self.homeManagerModules.kitty
              self.homeManagerModules.nautilus
              self.homeManagerModules.neovim
              self.homeManagerModules.niri
              self.homeManagerModules.noctalia
              self.homeManagerModules.packages
              self.homeManagerModules.variables
              self.homeManagerModules.vicinae
            ];

            home.username = config.myConfig.username;
            home.homeDirectory = "/home/${config.myConfig.username}";
            home.stateVersion = "25.11";
          };
        };
      })
    ];
  };
}
