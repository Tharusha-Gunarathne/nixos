{...}: {
  flake.nixosModules.displayManager = {pkgs, ...}: {
    services.greetd = {
      enable = true;
      settings.default_session = {
        command = "${pkgs.tuigreet}/bin/tuigreet --cmd niri-session";
        user = "greeter";
      };
    };
    services.seatd.enable = true;
  };
}
