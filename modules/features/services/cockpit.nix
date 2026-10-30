{...}: {
  flake.nixosModules.cockpit = {
    pkgs,
    lib,
    ...
  }: let
    nixosIcon = "${pkgs.nixos-icons}/share/icons/hicolor/256x256/apps/nix-snowflake.png";
  in {
    environment.systemPackages = with pkgs; [
      cockpit
    ];

    services.cockpit = {
      enable = true;
      port = 9090;
      openFirewall = false;
      settings = {
        WebService = {
          AllowUnencrypted = true;
          Origins = lib.mkForce "http://localhost:9090 http://127.0.0.1:9090";
        };
      };
    };

    # The desktop launcher only needs local access to this admin interface.
    systemd.sockets.cockpit.listenStreams = lib.mkForce ["" "127.0.0.1:9090"];

    home-manager.sharedModules = [
      {
        xdg.desktopEntries.cockpit = {
          name = "Cockpit";
          comment = "Web-based server administration";
          exec = "xdg-open http://localhost:9090";
          icon = nixosIcon;
          terminal = false;
          categories = ["System"];
        };
      }
    ];
  };
}
