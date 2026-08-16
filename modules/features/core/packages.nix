{inputs, ...}: {
  flake.nixosModules.packages = {
    pkgs,
    config,
    ...
  }: {
    nixpkgs.config.permittedInsecurePackages = [
      "electron-39.8.10"
      "electron-40.10.5"
      "pnpm-10.29.2"
    ];

    nixpkgs.overlays = [
      (final: prev: {
        pythonPackagesExtensions =
          prev.pythonPackagesExtensions
          ++ [
            (pyfinal: pyprev: {
              # nixpkgs bug: textstat's derivation says 0.7.13 but the actual
              # fetched wheel's METADATA still says 0.7.12 (version bumped
              # without content changing). Correct the label to match reality
              # instead of suppressing the check.
              textstat = pyprev.textstat.overridePythonAttrs (old: {
                version = "0.7.13";
              });
            })
          ];
      })
    ];

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

        # Desktop apps
        ente-auth
        bitwarden-desktop
        btop
        onlyoffice-desktopeditors
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
        planify
        varia
        virtualbox

        # System management
        mission-center

        # App-specific packages
        inputs.monique.packages.${pkgs.system}.default
      ];
    };
  };
}
