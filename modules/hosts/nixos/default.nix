{
  self,
  inputs,
  ...
}: {
  flake.nixosConfigurations.nixos = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      inputs.home-manager.nixosModules.home-manager
      self.nixosModules.nixosHardware
      self.nixosModules.nixosConfiguration
      ({config, ...}: {
        home-manager.useGlobalPkgs = true;
        home-manager.useUserPackages = true;
        home-manager.backupFileExtension = "backup";

        home-manager.users."${config.myConfig.primaryUser}" = {
          home.username = config.myConfig.primaryUser;
          home.homeDirectory = "/home/${config.myConfig.primaryUser}";
          home.stateVersion = "25.11";
        };
      })
    ];
  };
}
