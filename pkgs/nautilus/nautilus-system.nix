# Nautilus services, terminal integration, and extension path wiring.
{ pkgs, ... }:

{
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

  environment.pathsToLink = [
    "/share/nautilus-python/extensions"
  ];

  environment.sessionVariables = {
    NAUTILUS_4_EXTENSION_DIR = "${pkgs.nautilus-python}/lib/nautilus/extensions-4";
  };
}
  
