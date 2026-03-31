{ self, ... }: {
  flake.nixosModules.nautilus = { pkgs, ... }: {
    environment.systemPackages = with pkgs; [
      nautilus
      nautilus-python
      gvfs
      glib
      xdg-utils
      gsettings-desktop-schemas
    ];

    services.gvfs.enable = true;
    services.tumbler.enable = true;
    programs.dconf.enable = true;

    programs.nautilus-open-any-terminal = {
      enable = true;
      terminal = "kitty";
    };

    environment.pathsToLink = [ "/share/nautilus-python/extensions" ];

    environment.sessionVariables.NAUTILUS_4_EXTENSION_DIR =
      "${pkgs.nautilus-python}/lib/nautilus/extensions-4";
  };

  flake.homeManagerModules.nautilus = { lib, ... }:
  let
    sourceDir = ./extensions;
    extensionFiles = builtins.attrNames (
      lib.filterAttrs (name: type: type == "regular" && lib.hasSuffix ".py" name)
        (builtins.readDir sourceDir)
    );
  in {
    xdg.dataFile = builtins.listToAttrs (map (name: {
      name = "nautilus-python/extensions/${name}";
      value = { source = sourceDir + "/${name}"; };
    }) extensionFiles);
  };
}
