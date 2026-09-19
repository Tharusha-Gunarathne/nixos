{...}: {
  flake.nixosModules.displayManager = {
    config,
    lib,
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
      # Look (wallpaper, palette, font, layout) comes from Sync -- don't set
      # those here, greeter.toml wins over sync.toml.
      settings = {
        cursor.size = 24;
        session.default = "Niri";
        user.default = username; # skip the user picker, open on password
        # Empty Enter hands off to the fingerprint reader (see fingerprint.nix).
        auth.allow_empty_password = true;
        appearance = {
          scheme = "Synced"; # pin to the shell's colors
          password_style = "random"; # match the shell lock screen
        };
      };
    };

    # Avatar: AccountsService defaulted IconFile to ~/.face, which the
    # greeter user can't read (home is 0700). Copy the shell's avatar into
    # AccountsService's own world-readable icon store before the daemon
    # reads its user files.
    systemd.services.accounts-daemon.preStart = ''
      src=${lib.escapeShellArg "/home/${username}/avatar.png"}
      icon=/var/lib/AccountsService/icons/${username}
      user=/var/lib/AccountsService/users/${username}
      if [ -f "$src" ]; then
        install -D -m 0644 "$src" "$icon"
        mkdir -p "$(dirname "$user")"
        if [ -f "$user" ] && grep -q '^Icon=' "$user"; then
          sed -i "s|^Icon=.*|Icon=$icon|" "$user"
        elif [ -f "$user" ]; then
          sed -i "/^\[User\]/a Icon=$icon" "$user"
        else
          printf '[User]\nIcon=%s\nSystemAccount=false\n' "$icon" > "$user"
        fi
      fi
    '';

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
