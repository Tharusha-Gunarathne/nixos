{...}: {
  flake.nixosModules.performance = {pkgs, ...}: let
    # Store closures of apps worth having hot in page cache right after login.
    prefetchClosure = pkgs.closureInfo {
      rootPaths = with pkgs; [brave nautilus];
    };

    # Windows-Prefetch-style warmup: reads app binaries/libs and the Brave
    # profile into page cache so the first launch after login skips disk I/O.
    # Runs at idle I/O priority; the cache is reclaimable, so it never
    # pressures memory.
    appPrefetch = pkgs.writeShellScript "app-prefetch" ''
      vmtouch=${pkgs.vmtouch}/bin/vmtouch

      xargs -a ${prefetchClosure}/store-paths $vmtouch -tq -m 256M

      brave_dir="$HOME/.config/BraveSoftware/Brave-Browser"
      if [ -d "$brave_dir" ]; then
        $vmtouch -tq -m 64M \
          -i 'Cache' -i 'Code Cache' -i 'GPUCache' -i 'DawnGraphiteCache' \
          -i 'DawnWebGPUCache' -i 'GrShaderCache' -i 'ShaderCache' \
          -i 'File System' -i 'Service Worker' -i 'Shared Dictionary' \
          -i 'component_crx_cache' -i 'optimization_guide_model_store' \
          "$brave_dir"
      fi
    '';
  in {
    services.ananicy = {
      enable = true;
      package = pkgs.ananicy-cpp.overrideAttrs (old: {
        env =
          (old.env or {})
          // {
            CXXFLAGS = "${old.env.CXXFLAGS or ""} -include cstring -include cstdint";
          };
      });
      rulesProvider = pkgs.ananicy-rules-cachyos;
    };

    systemd.user.services.app-prefetch = {
      description = "Prefetch frequently used apps into page cache";
      wantedBy = ["graphical-session.target"];
      after = ["graphical-session.target"];
      partOf = ["graphical-session.target"];
      serviceConfig = {
        Type = "oneshot";
        ExecStart = appPrefetch;
        Nice = 19;
        IOSchedulingClass = "idle";
      };
    };
  };
}
