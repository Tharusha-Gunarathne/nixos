{inputs, ...}: {
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

    home-manager.users.${config.myConfig.primaryUser} = {...}: {
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
        ffmpeg
        ffmpegthumbnailer
        drawio
        localsend
        bleachbit
        timeshift
        obs-studio
        microsoft-edge
        handbrake
        qt6Packages.qt6ct
        sshfs
        fuse3
        # Noctalia plugin runtime dependencies (wallcards, monique, screen-toolkit)
        grim
        slurp
        tesseract
        imagemagick
        zbar
        curl
        jq
        wl-screenrec
        wf-recorder
        translate-shell
        gifski
        inputs.monique.packages.${pkgs.system}.default
      ];
    };
  };
}
