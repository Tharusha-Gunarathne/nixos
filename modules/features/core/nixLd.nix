{...}: {
  flake.nixosModules.nixLd = {pkgs, ...}: {
    # Allow running dynamically linked executables that aren't built for NixOS
    # (e.g. Zed extensions that ship prebuilt language servers).
    programs.nix-ld = {
      enable = true;

      # A small "common" set of libraries that covers many third-party binaries.
      # If a binary still fails with "cannot open shared object file", add the
      # missing library's package here.
      libraries = with pkgs; [
        stdenv.cc.cc
        zlib
        openssl
        curl
      ];
    };
  };
}
