{ self, ... }: {
  flake.nixosModules.nixosConfiguration = { ... }: {
    imports = [
      # core
      self.nixosModules.options
      self.nixosModules.users
      self.nixosModules.nixSettings
      # hardware
      self.nixosModules.audio
      self.nixosModules.bluetooth
      self.nixosModules.boot
      self.nixosModules.displayManager
      self.nixosModules.fonts
      self.nixosModules.locale
      self.nixosModules.network
      self.nixosModules.nvidia
      self.nixosModules.services
      # software
      self.nixosModules.gtk
      self.nixosModules.nautilus
      self.nixosModules.niri
      self.nixosModules.packages
      self.nixosModules.throne
    ];
  };
}
