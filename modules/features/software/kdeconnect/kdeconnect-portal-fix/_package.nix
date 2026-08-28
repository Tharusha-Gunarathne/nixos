{ lib, stdenv, cmake, pkg-config, wayland, wayland-protocols
, wayland-scanner, libxkbcommon, libei, qt6, src
}:

stdenv.mkDerivation {
  pname = "kdeconnect-portal-fix";
  version = "unstable-2026-08-28";
  inherit src;

  nativeBuildInputs = [ cmake pkg-config wayland-scanner qt6.wrapQtAppsHook ];
  buildInputs = [ wayland wayland-protocols libxkbcommon libei qt6.qtbase ];

  cmakeFlags = [ "-DCMAKE_BUILD_TYPE=Release" ];

  meta = with lib; {
    description = "xdg-desktop-portal RemoteDesktop backend for KDE Connect remote input on niri/wlroots";
    homepage = "https://github.com/iamnarayana/wayland-kdeconnect-fix";
    platforms = platforms.linux;
  };
}