{...}: {
  flake.nixosModules.flatpak = {pkgs, lib, ...}: {
    services.flatpak = {
      enable = true;

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
      ];

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