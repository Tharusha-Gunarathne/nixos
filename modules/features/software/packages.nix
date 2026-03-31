{ self, ... }: {
  flake.nixosModules.packages = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      vim
      git
      wget
      wl-clipboard
      brightnessctl
      tree
      vicinae
      xwayland-satellite
    ];
  };

  flake.homeManagerModules.packages = { pkgs, ... }: {
    home.packages = with pkgs; [
      brave
      kitty
      vscode
      bat
      throne
      inotify-tools
      fastfetch
      python3
      python3Packages.pip
    ];
  };
}
