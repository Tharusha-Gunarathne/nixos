{
  description = "Noctalia Independent Plugin Registry";
  
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # NOCTALIA MAIN
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = inputs: {
    noctalia-main = inputs.noctalia;
  };
}
