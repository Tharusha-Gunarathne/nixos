{inputs, ...}: {
  flake.nixosModules.packages = {
    pkgs,
    config,
    ...
  }: {
    environment.systemPackages = with pkgs; [
      # Core CLI
      vim
      git
      wget
      curl
      jq
      wl-clipboard
      brightnessctl
      tree
      ripgrep

      # Development tooling available system-wide
      nil

      # Session/runtime tooling shared by compositor + plugins
      xwayland-satellite
      qt6.qt5compat
      ffmpeg
      ffmpegthumbnailer
      imagemagick
      grim
      slurp
      tesseract
      zbar
      wl-screenrec
      wf-recorder
      translate-shell
      gifski

      # Filesystem helpers
      sshfs
      fuse3
    ];

    home-manager.users.${config.myConfig.primaryUser} = {...}: {
      home.packages = with pkgs; [
        # User CLI
        bat
        inotify-tools
        fastfetch

        # User development stack
        python3
        python3Packages.pip
        nodejs
        gcc

        # Desktop apps
        ente-auth
        bitwarden-desktop
        btop
        libreoffice
        ferdium
        drawio
        localsend
        bleachbit
        timeshift
        obs-studio
        microsoft-edge
        handbrake
        qt6Packages.qt6ct

        # App-specific packages
        inputs.monique.packages.${pkgs.system}.default
      ];
    };
  };
}
