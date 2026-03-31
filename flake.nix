{
  description = "Tharusha's NixOS Flake";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    noctalia.url = "path:./plugins/noctalia";
  };

  outputs = inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; }
      (inputs.import-tree ./modules);
}
