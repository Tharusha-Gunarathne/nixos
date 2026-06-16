{...}: {
  flake.nixosModules.power = {
    config,
    lib,
    pkgs,
    ...
  }: {
    services.power-profiles-daemon.enable = true;
    services.upower.enable = true;
    services.thermald.enable = true;

    # Configure lid switch behavior
    #   ignore = do nothing.
    #   suspend = sleep the system.
    #   hibernate = hibernate the system,
    #   poweroff = shut down the system.
    #   suspend-then-hibernate = Suspends first, then hibernates after a delay.
    #   reboot = reboot the system.
    #   kexec = Reboots into a new kernel without full reboot.
    services.logind.settings.Login = {
      HandleLidSwitch = "suspend-then-hibernate"; # when battery powered
      HandleLidSwitchDocked = "ignore"; # when docked/external monitor
      HandleLidSwitchExternalPower = "ignore"; # when plugged in
    };

    # Undervolt the CPU
    # To undervolt disable "Undervolt Protection" in the BIOS/UEFI, then find
    # stable undervolt values for your CPU and set them here.
    # "Undervolt Protection" is shown when "Legion Optimization" is enabled
    # in new Legion BIOS.
    # ===========================================================================
    services.undervolt = lib.mkIf config.myConfig.isUnderVoltEnabled {
      enable = true;
      coreOffset = -100;
      uncoreOffset = -80;
      gpuOffset = 0;
    };

    systemd.services.undervolt = lib.mkIf config.myConfig.isUnderVoltEnabled {
      serviceConfig.ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
    };

    systemd.services.cpu-power-limits = lib.mkIf config.myConfig.isUnderVoltEnabled {
      description = "Set CPU Power Limits";
      after = ["undervolt.service"];
      wantedBy = ["multi-user.target"];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        ExecStartPre = "${pkgs.coreutils}/bin/sleep 5";
        ExecStart = pkgs.writeShellScript "set-power-limits" ''
          ${pkgs.undervolt}/bin/undervolt --power-limit-long 105 28 --power-limit-short 162 56
        '';
      };
    };
    # ===========================================================================
  };
}
