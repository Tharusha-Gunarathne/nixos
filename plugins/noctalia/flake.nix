{
  description = "Noctalia Independent Plugin Registry";

  inputs = {
    # NOCTALIA MAIN
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
    };

    # Plugins
    noctalia-official-plugins = {
      url = "github:noctalia-dev/official-plugins";
      flake = false;
    };

    noctalia-community-plugins = {
      url = "github:noctalia-dev/community-plugins";
      flake = false;
    };

    # Locally authored plugins, kept here (not in the root flake) so
    # ~/nixos/flake.nix stays free of per-plugin entries. `flake = false`
    # means this is a plain source fetch with no nixpkgs and no lock of its
    # own, so it carries none of the follows/hash-divergence risk that a
    # nested *flake* input would.
    noctalia-hotspot-plugin = {
      url = "github:tharusha-gunarathne/noctalia-hotspot";
      flake = false;
    };
  };

  outputs = {self, ...} @ inputs: {
    inherit inputs;
  };
}
