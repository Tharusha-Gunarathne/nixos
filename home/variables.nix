# Session environment variables for Wayland and NVIDIA behavior.
{ config, pkgs, inputs, username, ... }:

{
  home.sessionVariables = {
    LIBVA_DRIVER_NAME = "nvidia";
    XDG_SESSION_TYPE = "wayland";
    GBM_BACKEND = "nvidia-drm";
    __GLX_VENDOR_LIBRARY_NAME = "nvidia";
    WLR_NO_HARDWARE_CURSORS = "1";
    NIXOS_OZONE_WL = "1";
    GTK_THEME = "Adwaita-dark";
    XDG_DATA_DIRS = "$XDG_DATA_DIRS:/run/current-system/sw/share";
    GI_TYPELIB_PATH = "/run/current-system/sw/lib/girepository-1.0";
  };
}
