{
  description = "Modular NixOS configuration";

  inputs = {
    flake-parts.url = "github:hercules-ci/flake-parts";
    import-tree.url = "github:vic/import-tree";

    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    # Third Party Plugins
    niri-flake.url = "github:sodiboo/niri-flake";
    noctalia.url = "path:./plugins/noctalia";
    vicinae.url = "path:./plugins/vicinae";
    sources.url = "path:./plugins/sources";
    spicetify-nix = {
      url = "github:Gerg-L/spicetify-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix4vscode = {
      url = "github:nix-community/nix4vscode";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nixcord.url = "github:FlameFlag/nixcord";
    monique = {
      url = "github:ToRvaLDz/monique";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    nix-flatpak.url = "github:gmodena/nix-flatpak";
  };

  outputs = inputs: let
    # ── Load machine-specific config from .env.local (gitignored, TOML) ────────
    # Copy .env.local.example → .env.local and fill in your values.
    # The abort gives a clear error on fresh clones before the file exists.
    localConfigPath = builtins.getEnv "NIXOS_LOCAL_CONFIG";
    localConfig =
      if localConfigPath != "" && builtins.pathExists localConfigPath
      then builtins.fromTOML (builtins.readFile localConfigPath)
      else
        abort ''

          Local configuration not found!

          This file holds machine-specific values (UUIDs, API keys, paths).
          Create it from the template before building:

            cp .env.local.example .env.local
            # then edit .env.local and fill in your values
            export NIXOS_LOCAL_CONFIG="$PWD/.env.local"

          Evaluate with --impure and the Git flake (.#), never path:.
          This keeps ignored files and credentials out of the flake source.

        '';
  in
    inputs.flake-parts.lib.mkFlake {inherit inputs;} ({...}: {
      # Import every module discovered by import-tree under ./modules.
      imports = [(inputs.import-tree ./modules)];

      # _module.args injects localConfig into the argument set of every
      # flake-parts module, so modules can declare:
      #   { localConfig, ... }: { flake.nixosModules.foo = ...; }
      # This is the correct flake-parts mechanism — not flake.specialArgs,
      # which is not a valid option.
      _module.args.localConfig = localConfig;
    });
}
