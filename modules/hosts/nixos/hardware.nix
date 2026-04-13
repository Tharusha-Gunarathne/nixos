{...}: {
  flake.nixosModules.nixosHardware = {
    config,
    lib,
    pkgs,
    modulesPath,
    ...
  }: let
    username = config.myConfig.username;
    uid = toString config.users.users.${username}.uid;

    # My Drives - UUID
    root = "00000000-0000-0000-0000-000000000000";
    boot = "6A90-3D23";
    drives = [
      {
        name = "D_Drive";
        uuid = "01DCC7D0F4666AF0";
      }
      {
        name = "E_Drive";
        uuid = "ACAE0ACAAE0A8D50";
      }
    ];

    # Helper function to create NTFS data mounts with consistent options
    mkNtfsDataMount = {
      name,
      uuid
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
    ] ++ map mkNtfsDataMount drives);

    swapDevices = [];

    nixpkgs.hostPlatform = lib.mkDefault "x86_64-linux";
    hardware.cpu.intel.updateMicrocode = lib.mkDefault config.hardware.enableRedistributableFirmware;
  };
}
