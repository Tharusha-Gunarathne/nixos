{ self, ... }: {
  flake.nixosModules.nixosHardware = { config, lib, pkgs, modulesPath, ... }: {
    imports = [ (modulesPath + "/installer/scan/not-detected.nix") ];

    boot.initrd.availableKernelModules = [ "xhci_pci" "nvme" "thunderbolt" "usbhid" "usb_storage" "sd_mod" "sdhci_pci" ];
    boot.initrd.kernelModules = [ ];
    boot.kernelModules = [ "kvm-intel" ];
    boot.extraModulePackages = [ ];

    fileSystems."/" = {
      device = "/dev/disk/by-uuid/00000000-0000-0000-0000-000000000000";
      fsType = "ext4";
    };

    fileSystems."/boot" = {
      device = "/dev/disk/by-uuid/0000-0000";
      fsType = "vfat";
      options = [ "fmask=0022" "dmask=0022" ];
    };

    swapDevices = [ ];

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
