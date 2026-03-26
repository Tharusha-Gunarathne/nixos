# Throne system-level configuration extension point
{ config, lib, pkgs, username, ... }:

{
  security.wrappers.throne = {
    owner = "root";
    group = "root";
    capabilities = "cap_net_admin+ep";
    source = "${pkgs.throne}/bin/Throne";
  };
}
