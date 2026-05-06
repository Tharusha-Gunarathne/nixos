{...}: {
  flake.nixosModules.cockpit = {
    config,
    pkgs,
    lib,
    ...
  }: {
    environment.systemPackages = with pkgs; [
      cockpit
    ];

    services.cockpit = {
      enable = true;
      port = 9090;
      openFirewall = true;
      settings = {
        WebService = {
          AllowUnencrypted = true;
          Origins = lib.mkForce "http://localhost:9090 http://127.0.0.1:9090";
        };
      };
    };
  };
}
