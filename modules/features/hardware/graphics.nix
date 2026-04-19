{...}: {
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

    hardware = {
      nvidia = {
        modesetting.enable = true;
        open = false;
        nvidiaSettings = true;
        package = config.boot.kernelPackages.nvidiaPackages.stable;

        powerManagement.enable = false; # this is the main culprit
        powerManagement.finegrained = false;

        prime = {
          offload.enable = true;
          offload.enableOffloadCmd = true;
          intelBusId = "PCI:0:2:0";
          nvidiaBusId = "PCI:1:0:0";
        };
      };

      graphics = {
        enable = true;
        extraPackages = with pkgs; [
          intel-media-driver
          intel-vaapi-driver
          libva-vdpau-driver
          libva-utils
          libvdpau-va-gl
          nvidia-vaapi-driver
        ];
      };
    };
  };
}
