{localConfig, ...}: {
  flake.nixosModules.graphics = {
    config,
    pkgs,
    ...
  }: {
    services.xserver.videoDrivers = ["nvidia"];

    # Fix hung kworker deadlock on shutdown/reboot
    boot.kernel.sysctl = {
      "kernel.sysrq" = 1; # enable REISUB escape hatch
      "kernel.hung_task_timeout_secs" = 15; # don't hang forever
    };

    boot.kernelParams = [
      "nvidia.NVreg_PreserveVideoMemoryAllocations=0"
      "nvidia.NVreg_EnableGPUFirmware=0"
    ];

    systemd.services.display-manager.serviceConfig.TimeoutStopSec = "10s";

    hardware = {
      nvidia = {
        modesetting.enable = true;
        open = false;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;

        powerManagement.enable = false; # main culprit of shutdown hangs
        powerManagement.finegrained = false;

        prime = {
          offload.enable = true;
          offload.enableOffloadCmd = true;
          intelBusId = localConfig.hardware.intel_bus_id;
          nvidiaBusId = localConfig.hardware.nvidia_bus_id;
        };
      };

      graphics = {
        enable = true;
        # For 32 bit applications
        enable32Bit = true; # Before 24.11: hardware.opengl.driSupport32Bit
        extraPackages = with pkgs; [
          intel-media-driver
          intel-vaapi-driver
          libva-vdpau-driver
          libva-utils
          libvdpau-va-gl
          nvidia-vaapi-driver
          rocmPackages.clr
        ];
      };
    };

    environment.variables.__GL_SHADER_DISK_CACHE_SIZE = "12000000000"; # 12GB, cuts stutter from shader recompiles
  };
}
