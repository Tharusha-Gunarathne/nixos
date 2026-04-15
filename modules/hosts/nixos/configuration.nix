{self, ...}: {
  flake.nixosModules.nixosConfiguration = {...}: {
    imports = [
      # core
      self.nixosModules.commandShortcuts
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
      self.nixosModules.swap
      # software
      self.nixosModules.git
      self.nixosModules.gtk
      self.nixosModules.kitty
      self.nixosModules.nautilus
      self.nixosModules.niri
      self.nixosModules.noctalia
      self.nixosModules.mpv
      self.nixosModules.packages
      self.nixosModules.throne
      self.nixosModules.variables
      self.nixosModules.vicinae
      self.nixosModules.neovim
      self.nixosModules.spotify
      self.nixosModules.fish
      self.nixosModules.vscode
      self.nixosModules.lotion
      self.nixosModules.xdm
      self.nixosModules.brave
      self.nixosModules.ferdium
      self.nixosModules.discord
      self.nixosModules.obs
    ];
  };
}
