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
  };

  outputs = {self, ...} @ inputs: {
    inherit inputs; 
  };
}
