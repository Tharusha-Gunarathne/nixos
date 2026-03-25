{
  description = "Noctalia Independent Plugin Registry";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    # NOCTALIA MAIN
    noctalia = {
      url = "github:noctalia-dev/noctalia-shell";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # noctalia-qs = {
    #   url = "github:noctalia-dev/noctalia-qs";
    #   inputs.nixpkgs.follows = "nixpkgs";
    # };

    # NOCTALIA PLUGINS
    # Each plugin tracks its own version in its own lockfile entry    
    fancy-audiovisualizer = {
      url = "github:noctalia-dev/noctalia-plugins?dir=fancy-audiovisualizer"; 
      flake = false; 
    };

    kde-connect = { 
      url = "github:noctalia-dev/noctalia-plugins?dir=kde-connect"; 
      flake = false; 
    };

    keybind-cheatsheet = {
      url = "github:noctalia-dev/noctalia-plugins?dir=keybind-cheatsheet"; 
      flake = false; 
    };

    niri-auto-tile = {
      url = "github:noctalia-dev/noctalia-plugins?dir=niri-auto-tile"; 
      flake = false; 
    };
    
    polkit-agent = { 
      url = "github:noctalia-dev/noctalia-plugins?dir=polkit-agent"; 
      flake = false; 
    };

    screen-recorder = {
      url = "github:noctalia-dev/noctalia-plugins?dir=screen-recorder"; 
      flake = false; 
    };
  };

  outputs = inputs: {
    noctalia-main = inputs.noctalia;

    plugins = {
      # Add every plugin name here
      inherit (inputs) 
        fancy-audiovisualizer 
        kde-connect 
        keybind-cheatsheet 
        niri-auto-tile 
        polkit-agent 
        screen-recorder;
    };
  };
}
