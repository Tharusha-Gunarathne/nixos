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
      rar
      ntfs3g

      # Browser
      firefox

      # Hardware management
      efibootmgr
      intel-undervolt

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

    home-manager.users.${config.myConfig.primaryUser} = {pkgs, ...}: {
      home.packages = with pkgs; [
        # User CLI
        bat
        inotify-tools
        yazi
        fzf
        brotab

        # User development stack
        python314
        uv
        python314Packages.pip
        nodejs
        lmstudio
        claude-code
        
        # Desktop apps
        ente-auth
        bitwarden-desktop
        btop
        libreoffice
        drawio
        localsend
        bleachbit
        timeshift
        microsoft-edge
        qt6Packages.qt6ct
        proton-vpn
        kdePackages.ark
        qbittorrent
        obsidian
        qalculate-gtk

        # System management
        mission-center

        # App-specific packages
        inputs.monique.packages.${pkgs.system}.default
      ];
    };
  };
}
