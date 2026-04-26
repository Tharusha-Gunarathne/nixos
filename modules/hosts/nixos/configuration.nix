{self, ...}: {
  flake.nixosModules.nixosConfiguration = {...}: {
    imports = [
      # core
      self.nixosModules.nixSettings
      self.nixosModules.options
      self.nixosModules.packages
      self.nixosModules.shellAliases
      self.nixosModules.users
      # hardware
      self.nixosModules.audio
      self.nixosModules.bluetooth
      self.nixosModules.boot
      self.nixosModules.displayManager
      self.nixosModules.fonts
      self.nixosModules.graphics
      self.nixosModules.locale
      self.nixosModules.network
      self.nixosModules.services
      self.nixosModules.swap
      # software
      self.nixosModules.mpv
      self.nixosModules.nautilus
      self.nixosModules.niri
      self.nixosModules.noctalia
      self.nixosModules.brave
      self.nixosModules.discord
      self.nixosModules.ferdium
      self.nixosModules.fish
      self.nixosModules.flatpak
      self.nixosModules.git
      self.nixosModules.kitty
      self.nixosModules.lotion
      self.nixosModules.neovim
      self.nixosModules.obs
      self.nixosModules.shutterEncoder
      self.nixosModules.spotify
      self.nixosModules.throne
      self.nixosModules.vicinae
      self.nixosModules.vscode
      self.nixosModules.xdm
      self.nixosModules.fastfetch
      # user
      self.nixosModules.gtk
      self.nixosModules.variables
      self.nixosModules.desktopEntries
    ];
  };
}
