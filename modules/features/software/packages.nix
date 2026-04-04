{self, ...}: {
  flake.nixosModules.packages = {
    pkgs,
    config,
    ...
  }: {
    environment.systemPackages = with pkgs; [
      vim
      git
      wget
      wl-clipboard
      brightnessctl
      tree
      xwayland-satellite
      nil
      ripgrep
      gedit
    ];

    home-manager.users.${config.myConfig.username} = {...}: {
      home.packages = with pkgs; [
        brave
        bat
        throne
        inotify-tools
        fastfetch
        python3
        python3Packages.pip
        ente-auth
        bitwarden-desktop
        nodejs
        gcc
        btop
      ];
    };
  };
}
