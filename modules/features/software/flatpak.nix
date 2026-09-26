{...}: {
  flake.nixosModules.flatpak = {
    pkgs,
    lib,
    config,
    ...
  }: let
    nvidiaVersion = config.boot.kernelPackages.nvidiaPackages.stable.version;
    nvidiaGLExtension = "org.freedesktop.Platform.GL.nvidia-" + builtins.replaceStrings ["."] ["-"] nvidiaVersion;
  in {
    services.flatpak = {
      enable = true;
      uninstallUnmanaged = true;

      remotes = lib.mkOptionDefault [
        {
          name = "flathub";
          location = "https://flathub.org/repo/flathub.flatpakrepo";
        }
      ];

      packages = [
        {
          appId = "fr.handbrake.ghb";
          origin = "flathub";
        }
        {
          appId = "com.usebottles.bottles";
          origin = "flathub";
        }
        {
          appId = nvidiaGLExtension;
          origin = "flathub";
        }
      ];

      overrides = {
        "com.usebottles.bottles".Context.filesystems = ["home"];
      };

      update.auto = {
        enable = true;
        onCalendar = "weekly";
      };
    };

    fonts.fontDir.enable = true;

    xdg.portal = {
      enable = true;
      extraPortals = [pkgs.xdg-desktop-portal-gtk];
    };

    environment.systemPackages = [pkgs.flatpak];
  };
}