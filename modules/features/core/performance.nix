{...}: {
  flake.nixosModules.performance = {pkgs, ...}: {
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
  };
}
