{ self, ... }: {
  flake.nixosModules.packages = { pkgs, config, ... }: {
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

    home-manager.users.${config.myConfig.username} = { ... }: {
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
  };
}
