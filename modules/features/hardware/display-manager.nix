{...}: {
  flake.nixosModules.displayManager = {
    config,
    pkgs,
    ...
  }: let
    username = config.myConfig.primaryUser;
    greeterPkg = config.services.displayManager.noctalia-greeter.package;
  in {
    # Noctalia Greeter on greetd (nixpkgs module). Appearance (wallpaper,
    # palette, font, monitor layout) is pushed from the shell via
    # [shell.greeter_sync] in noctalia/settings.toml.
    services.displayManager.noctalia-greeter = {
      enable = true;
      cursorTheme = {
        package = pkgs.bibata-cursors;
        name = "Bibata-Modern-Ice";
      };
      settings = {
        cursor.size = 24;
        session.default = "Niri";
      };
    };

    # The greeter scans /run/current-system/sw/share/wayland-sessions,
    # which NixOS doesn't link by default.
    environment.pathsToLink = ["/share/wayland-sessions"];

    # Sync runs `pkexec noctalia-greeter-apply-appearance --sync`; the
    # nixpkgs module doesn't ship the passwordless rule or pkexec wrapper
    # (upstream's `passwordless-sync-users` does -- this mirrors it).
    security.polkit.enablePkexecWrapper = true;
    security.polkit.extraConfig = ''
      polkit.addRule(function(action, subject) {
        var allowedUsers = ${builtins.toJSON [username]};
        if (action.id == "org.noctalia.greeter.sync-appearance" &&
            action.lookup("program") == "${greeterPkg}/bin/noctalia-greeter-apply-appearance" &&
            action.lookup("user") == "root" &&
            subject.local && subject.active &&
            allowedUsers.indexOf(subject.user) >= 0) {
          return polkit.Result.YES;
        }
      });
    '';
  };
}
