# Entry point flake wiring system and home modules for this machine.
{
  description = "Tharusha's NixOS Flake";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia.url = "path:./plugins/noctalia";
    
    # noctalia = {
    #   url = "github:noctalia-dev/noctalia-shell";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # noctalia-qs = {
    #   url = "github:noctalia-dev/noctalia-qs";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

  };

  outputs = inputs@{ flake-parts, nixpkgs, home-manager, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [ "x86_64-linux" ];

      perSystem = { pkgs, ... }: {
        formatter = pkgs.alejandra;
      };

      flake =
        let
          system = "x86_64-linux";
          username = "tharusha-gunarathne";
          # baseDir = "/home/${username}/nixos-configs/structure";
          baseDir = toString ./.;
        in {
          nixosConfigurations.nixos = nixpkgs.lib.nixosSystem {
            inherit system;
            specialArgs = { inherit inputs username baseDir; };

            modules = [
              ./system/default.nix
              home-manager.nixosModules.home-manager
              {
                home-manager = {
                  useGlobalPkgs = true;
                  useUserPackages = true;
                  users.${username} = import .REDACTED-HOME.nix;
                  extraSpecialArgs = { inherit inputs username baseDir; };
                  backupFileExtension = "backup";
                };
              }
            ];
          };
        };
    };
}
