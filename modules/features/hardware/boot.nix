{...}: {
  flake.nixosModules.boot = {pkgs, ...}: let
    regularDarkTheme = pkgs.fetchFromGitHub {
      owner = "m3h3d1ha2an";
      repo = "refind-regular-dark";
      rev = "2683ab842c19bd334331276a48a2029f55267cd1";
      hash = "sha256-GrTrFy+PmEh6M3hQgAJWJfnqjiwOgHGkvQatB9P1wds=";
    };

    themeName = "rEFInd-Regular-Dark";
    nixosIcon = "${pkgs.nixos-icons}/share/icons/hicolor/256x256/apps/nix-snowflake.png";
    # Clearly larger than theme defaults.
    bigIconSize = 256;
    smallIconSize = 96;
    # Keep Windows auto-detected, but override which icon it uses.
    windowsIconSource = "os_win11.png";
    refindConf = pkgs.writeText "refind.conf" ''
      icons_dir themes/rEFInd-Regular-Dark/icons
      big_icon_size ${toString bigIconSize}
      small_icon_size ${toString smallIconSize}
      banner themes/rEFInd-Regular-Dark/icons/bg_dark.png
      selection_big themes/rEFInd-Regular-Dark/icons/selection_dark-big.png
      selection_small themes/rEFInd-Regular-Dark/icons/selection_dark-small.png
      font themes/rEFInd-Regular-Dark/fonts/source-code-pro-extralight-14.png
      hideui singleuser,hints

      scanfor manual,internal,external,optical
      scan_all_linux_kernels false
      dont_scan_dirs EFI/nixos,EFI/systemd,EFI/refind,EFI/BOOT
      dont_scan_files systemd-bootx64.efi,BOOTX64.EFI,grubx64.efi,shimx64.efi,mmx64.efi
      use_nvram false
      timeout 8
      default_selection "NixOS,Windows"

      menuentry "NixOS" {
        icon /EFI/refind/themes/rEFInd-Regular-Dark/icons/os_nixos.png
        loader /EFI/systemd/systemd-bootx64.efi
      }
    '';
  in {
    hardware.uinput.enable = true;
    boot.kernelModules = ["uinput"];

    boot.loader = {
      efi = {
        canTouchEfiVariables = true;
        efiSysMountPoint = "/boot";
      };

      grub.enable = false;
      systemd-boot.enable = true;
      refind.enable = false;
    };

    system.activationScripts.refindManualLauncher.text = ''
      set -eu

      refindShare="${pkgs.refind}/share/refind"
      refindDir="/boot/EFI/refind"
      themeDir="$refindDir/themes/${themeName}"

      install -d -m 0755 "$refindDir"
      install -d -m 0755 "$themeDir"

      # Keep core rEFInd assets up-to-date for theme rendering and icon fallbacks.
      cp -f "$refindShare/refind_x64.efi" "$refindDir/refind_x64.efi"
      cp -f "$refindShare/refind_x64.efi" "$refindDir/BOOTX64.EFI"
      cp -r -f "$refindShare/fonts" "$refindDir/"
      cp -r -f "$refindShare/icons" "$refindDir/"

      ${pkgs.coreutils}/bin/rm -rf "$themeDir"
      install -d -m 0755 "$themeDir"
      cp -r -f "${regularDarkTheme}/." "$themeDir/"

      # Theme switch cleanup: remove old Nord assets from previous generations.
      ${pkgs.coreutils}/bin/rm -rf "$refindDir/themes/nord"

      ${pkgs.coreutils}/bin/rm -f "$themeDir/icons/os_nixos.png" "$themeDir/icons/os_nixos-alt.png"
      cp -f "${nixosIcon}" "$themeDir/icons/os_nixos.png"
      cp -f "${nixosIcon}" "$themeDir/icons/os_nixos-alt.png"

      # Override auto-detected Windows icon without hardcoding any Windows boot stanza.
      if [ -f "$themeDir/icons/${windowsIconSource}" ]; then
        cp -f "$themeDir/icons/${windowsIconSource}" "$themeDir/icons/os_win.png"
        cp -f "$themeDir/icons/${windowsIconSource}" "$themeDir/icons/os_win8.png"
      fi

      # Reset persisted tool visibility state to avoid duplicated tool rows.
      install -d -m 0755 "$refindDir/vars"
      ${pkgs.coreutils}/bin/rm -f "$refindDir/vars/ShowTools" "$refindDir/vars/HiddenTools"

      cp -f "${refindConf}" "$refindDir/refind.conf"
    '';
  };
}
