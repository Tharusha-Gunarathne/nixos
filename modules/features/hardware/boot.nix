{inputs, ...}: {
  flake.nixosModules.boot = {pkgs, ...}: let
    refindPin = inputs.sources.sourcePins.refindRegularDark;
    regularDarkTheme = pkgs.fetchFromGitHub refindPin;

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
      systemd-boot.configurationLimit = 10;
      refind.enable = false;
    };

    system.activationScripts.refindManualLauncher.text = ''
      set -eu

      refindShare="${pkgs.refind}/share/refind"
      refindDir="/boot/EFI/refind"
      themeDir="$refindDir/themes/${themeName}"

      install -d -m 0755 "$refindDir"
      install -d -m 0755 "$themeDir"

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

      if [ -f "$themeDir/icons/${windowsIconSource}" ]; then
        cp -f "$themeDir/icons/${windowsIconSource}" "$themeDir/icons/os_win.png"
        cp -f "$themeDir/icons/${windowsIconSource}" "$themeDir/icons/os_win8.png"
      fi

      install -d -m 0755 "$refindDir/vars"
      ${pkgs.coreutils}/bin/rm -f "$refindDir/vars/ShowTools" "$refindDir/vars/HiddenTols"

      cp -f "${refindConf}" "$refindDir/refind.conf"

      # Register rEFInd in UEFI boot entries if not already present.
      if ! ${pkgs.efibootmgr}/bin/efibootmgr | grep -q "rEFInd"; then
        DISK=$(${pkgs.util-linux}/bin/lsblk -no pkname $(${pkgs.util-linux}/bin/findmnt -n -o SOURCE /boot) | head -1)
        PART=$(${pkgs.util-linux}/bin/lsblk -no MAJ:MIN $(${pkgs.util-linux}/bin/findmnt -n -o SOURCE /boot) | cut -d: -f2)
        ${pkgs.efibootmgr}/bin/efibootmgr --create \
          --disk "/dev/$DISK" \
          --part "$PART" \
          --label "rEFInd" \
          --loader '\EFI\refind\refind_x64.efi' \
          --quiet || true
      fi
    '';

    systemd.services.refind-efi-register = {
      description = "Register rEFInd in UEFI boot entries";
      wantedBy = ["multi-user.target"];
      after = ["local-fs.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        if ! ${pkgs.efibootmgr}/bin/efibootmgr | grep -q "rEFInd"; then
          DISK=$(${pkgs.util-linux}/bin/lsblk -no pkname \
            $(${pkgs.util-linux}/bin/findmnt -n -o SOURCE /boot) | head -1)
          PART=$(${pkgs.util-linux}/bin/lsblk -no PARTN \
            $(${pkgs.util-linux}/bin/findmnt -n -o SOURCE /boot))
          ${pkgs.efibootmgr}/bin/efibootmgr --create \
            --disk "/dev/$DISK" \
            --part "$PART" \
            --label "rEFInd" \
            --loader '\EFI\refind\refind_x64.efi'
          echo "rEFInd registered in UEFI."
        else
          echo "rEFInd already registered, skipping."
        fi
      '';
    };
  };
}
