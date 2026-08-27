{...}: {
  flake.nixosModules.nixLd = {pkgs, lib, ...}: {
    programs.nix-ld = {
      enable = true;
      libraries = with pkgs; [
        stdenv.cc.cc.lib
        zlib
        openssl
        curl
      ];
    };

    # Separate from nix-ld: this covers *Nix-built* binaries (like uv's
    # python3.14-env venvs) that dlopen foreign prebuilt wheels (e.g.
    # onnxruntime's manylinux .so) and need real libstdc++ etc. on the
    # ordinary LD_LIBRARY_PATH, since they use nixpkgs' own ld.so and
    # never consult NIX_LD_LIBRARY_PATH.
    environment.variables.LD_LIBRARY_PATH = lib.makeLibraryPath (with pkgs; [
      stdenv.cc.cc.lib
      zlib
      openssl
      curl
      libffi
      ncurses
      bzip2
      sqlite
      xz
      expat
      zstd
    ]);
  };
}