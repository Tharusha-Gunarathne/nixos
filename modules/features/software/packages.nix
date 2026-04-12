{...}: {
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
        bat
        inotify-tools
        fastfetch
        python3
        python3Packages.pip
        ente-auth
        bitwarden-desktop
        nodejs
        gcc
        btop
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
        qt6Packages.qt6ct
      ];
    };
  };
}
