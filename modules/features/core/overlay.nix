{inputs, ...}: {
  flake.nixosModules.overlays = {...}: {
    nixpkgs.overlays = [
      # niri-flake: provides pkgs.niri-stable / pkgs.niri-unstable
      inputs.niri-flake.overlays.niri

      # niri.nix: libdisplay-info pinned to 0.2 (niri needs this exact version)
      (final: prev: let
        pin = inputs.sources.sourcePins.libdisplayInfo0_2;
      in {
        libdisplay-info_0_2 = prev.libdisplay-info.overrideAttrs (old: {
          version = pin.rev;
          src = prev.fetchFromGitLab {
            inherit (pin) domain owner repo rev hash;
          };
        });
      })

      # packages.nix: nixpkgs bug workaround, wheel METADATA lags the
      # derivation's declared version
      (final: prev: {
        pythonPackagesExtensions =
          prev.pythonPackagesExtensions
          ++ [
            (pyfinal: pyprev: {
              textstat = pyprev.textstat.overridePythonAttrs (old: {
                version = "0.7.13";
              });
            })
          ];
      })

      # kdeconnect-portal-fix: RemoteDesktop portal backend for niri
      (final: prev: {
        kdeconnect-portal-fix = final.callPackage
          ../software/kdeconnect/kdeconnect-portal-fix/_package.nix
          {
            src = final.fetchFromGitHub {
              inherit (inputs.sources.sourcePins.kdeconnectPortalFix) owner repo rev hash;
            };
          };
      })
    ];
  };
}