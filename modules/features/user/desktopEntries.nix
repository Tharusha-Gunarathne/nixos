{localConfig, ...}: {
  flake.nixosModules.desktopEntries = {config, lib, pkgs, ...}: {
    # Optional private launchers live only in the ignored local TOML file.
    home-manager.users.${config.myConfig.primaryUser}.xdg.desktopEntries =
      lib.mapAttrs (_: entry:
        builtins.removeAttrs entry ["command"]
        // lib.optionalAttrs (entry ? command) {
          exec = toString (pkgs.writeShellScript "local-desktop-launcher" entry.command);
        }) (localConfig.desktop_entries or {});
  };
}
