{...}: {
  flake.nixosModules.gns3 = {
    pkgs,
    config,
    lib,
    ...
  }: {
    environment.systemPackages = with pkgs; [
      gns3-gui
      gns3-server
      dynamips
      vpcs
    ];

    # ubridge must NOT be in systemPackages — only the wrapped version
    # should be in PATH, otherwise GNS3 finds the raw binary and tries
    # to setcap it (which fails on the read-only Nix store).
    security.wrappers.ubridge = {
      source = "${pkgs.ubridge}/bin/ubridge";
      capabilities = "cap_net_admin,cap_net_raw=ep";
      owner = "root";
      group = "ubridge";
      permissions = "u+rx,g+rx";
    };

    users.groups.ubridge = {};

    users.users.${config.myConfig.primaryUser}.extraGroups = ["ubridge"];

    # Point GNS3 server at the wrapped binary explicitly
    environment.etc."gns3/gns3_server.conf".text = lib.mkDefault ''
      [Server]
      ubridge_path = /run/wrappers/bin/ubridge
    '';
  };
}