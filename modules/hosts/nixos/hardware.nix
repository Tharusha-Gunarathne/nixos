{...}: {
  flake.nixosModules.nixosHardware = {
    config,
    lib,
    modulesPath,
    ...
  }: let
    username = config.myConfig.primaryUser;
    uid = toString config.users.users.${username}.uid;

    root = config.myConfig.storage.rootUuid;
    boot = config.myConfig.storage.bootUuid;
    drives = config.myConfig.storage.dataDrives;

    # Helper function to create NTFS data mounts with consistent options
    mkNtfsDataMount = {
      name,
      uuid,
    }: {
      "/mnt/${name}" = {
        device = "/dev/disk/by-uuid/${uuid}";
        fsType = "ntfs3";
        options = [
          "uid=${uid}"
          "gid=100"
          "rw"
          "nofail"
          "umask=022"
          "windows_names"
          "x-gvfs-show"
          "x-gvfs-name=${name}"
        ];
      };
    };
  in {
    imports = [(modulesPath + "/installer/scan/not-detected.nix")];

    boot.initrd.availableKernelModules = ["xhci_pci" "nvme" "thunderbolt" "usbhid" "usb_storage" "sd_mod" "sdhci_pci"];
    boot.initrd.kernelModules = [];
    boot.kernelModules = ["kvm-intel"];
    boot.extraModulePackages = [];

    fileSystems = lib.mkMerge ([
        {
          "/" = {
            device = "/dev/disk/by-uuid/${root}";
            fsType = "ext4";
          };

          "/boot" = {
            device = "/dev/disk/by-uuid/${boot}";
            fsType = "vfat";
            options = ["fmask=0022" "dmask=0022"];
          };
        }
      ]
      ++ map mkNtfsDataMount drives);

    swapDevices = [];

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
