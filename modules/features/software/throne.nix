{self, ...}: {
  flake.nixosModules.throne = {pkgs, ...}: {
    security.wrappers.throne = {
      owner = "root";
      group = "root";
      capabilities = "cap_net_admin+ep";
      source = "${pkgs.throne}/bin/Throne";
    };
  };
}
