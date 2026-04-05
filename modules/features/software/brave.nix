{...}: {
  flake.nixosModules.brave = {
    pkgs,
    config,
    lib,
    ...
  }: {
    environment.etc."brave/policies/managed/extensions.json".text = builtins.toJSON {
      ExtensionInstallForcelist = [
        "ddkjiahejlhfcafbddmgiahcphecmpfh" # uBlock Origin Lite
        "nngceckbapebfimnlniiiahkandclblb" # Bitwarden
      ];
    };
  };
}
