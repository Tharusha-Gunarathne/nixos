{self, ...}: {
  flake.nixosModules.nixosConfiguration = {...}: {
    imports = [
      # core
      self.nixosModules.nixSettings
      self.nixosModules.nixLd
      self.nixosModules.options
      self.nixosModules.packages
      self.nixosModules.overlays
      self.nixosModules.performance
      self.nixosModules.shellAliases
      self.nixosModules.users
      self.nixosModules.polkit
      self.nixosModules.homeManager
      self.nixosModules.journald
      # hardware
      self.nixosModules.audio
      self.nixosModules.bluetooth
      self.nixosModules.boot
      self.nixosModules.displayManager
      self.nixosModules.fonts
      self.nixosModules.graphics
      self.nixosModules.locale
      self.nixosModules.network
      self.nixosModules.power
      self.nixosModules.storage
      self.nixosModules.swap
      self.nixosModules.firmware
      self.nixosModules.keyboardLeds
      self.nixosModules.fingerprint
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
      self.nixosModules.kdeconnect
      self.nixosModules.kitty
      self.nixosModules.lotion
      self.nixosModules.obs
      # self.nixosModules.shutterEncoder
      self.nixosModules.spotify
      self.nixosModules.throne
      self.nixosModules.vicinae
      self.nixosModules.xdm
      self.nixosModules.fastfetch
      self.nixosModules.loupe
      self.nixosModules.openWebUI
      self.nixosModules.simpMusic
      self.nixosModules.tailscale
      self.nixosModules.wlrWhichKey
      self.nixosModules.gaming
      self.nixosModules.development
      #services
      self.nixosModules.cockpit
      self.nixosModules.hotspot
      self.nixosModules.virtualization
      # user
      self.nixosModules.gtk
      self.nixosModules.variables
      self.nixosModules.desktopEntries
    ];
  };
}
