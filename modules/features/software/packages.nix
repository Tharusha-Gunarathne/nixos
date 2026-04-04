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
        discord
        libreoffice
        ferdium
        mpv
        ffmpeg
        drawio
        localsend
        bleachbit
        timeshift
        obs-studio
        microsoft-edge
        handbrake
      ];
    };
  };
}
