{inputs, ...}: {
  flake.nixosModules.fingerprint = {
    config,
    pkgs,
    ...
  }: let
    pamServices = config.security.pam.services;

    # pam_fprintd fork: prompts for the password *while* the reader is
    # listening, so either one works at the same prompt. Module only.
    pin = inputs.sources.sourcePins.fprintGrosshack;
    fprintGrosshack = pkgs.stdenv.mkDerivation {
      pname = "pam-fprint-grosshack";
      version = "1.94.2";
      src = pkgs.fetchFromGitLab {inherit (pin) domain owner repo rev hash;};

      # pam_wrapper is only needed for the (disabled) test suite.
      postPatch = ''
        substituteInPlace meson.build \
          --replace-fail "dependency('pam_wrapper', required: get_option('pam'))" \
                         "dependency('pam_wrapper', required: false)"
      '';

      nativeBuildInputs = with pkgs; [meson ninja pkg-config perl python3];
      buildInputs = with pkgs; [glib libfprint polkit dbus systemdLibs pam];
      mesonFlags = [
        "-Dman=false"
        "-Dsystemd=false"
        "-Dpam_modules_dir=${placeholder "out"}/lib/security"
      ];
      env.PKG_CONFIG_POLKIT_GOBJECT_1_POLICYDIR = "${placeholder "out"}/share/polkit-1/actions";
    };

    # Run pam_fprintd *after* the password check instead of before it:
    # type the password as usual, or submit an empty password and touch
    # the sensor. (Stock ordering puts the finger first and blocks.)
    fingerprintAfterPassword = name: {
      rules.auth.fprintd.order = pamServices.${name}.rules.auth.unix.order + 10;
    };
  in {
    # Goodix 27c6:659a (goodixmoc driver) -- supported by stock libfprint.
    # Enroll with `fprintd-enroll`, verify with `fprintd-verify`.
    services.fprintd.enable = true;

    # greetd has no stack of its own -- it substacks "login", so this also
    # covers the greeter and TTYs. A password login still reaches
    # pam_gnome_keyring and unlocks the keyring; a fingerprint login can't.
    # The Noctalia lock screen also uses "login" but strips pam_fprintd and
    # runs password + fingerprint side by side itself.
    security.pam.services.login = fingerprintAfterPassword "login";

    # sudo: password and fingerprint at the same prompt. A match returns
    # success; a typed password is stored as PAM_AUTHTOK and checked by
    # pam_unix (try_first_pass) right after.
    security.pam.services.sudo = {
      fprintAuth = false;
      rules.auth.fprintd-grosshack = {
        order = pamServices.sudo.rules.auth.unix.order - 10;
        control = "sufficient";
        modulePath = "${fprintGrosshack}/lib/security/pam_fprintd_grosshack.so";
      };
    };

    # Noctalia's polkit dialog refuses empty submits, so password-first
    # would make the finger unreachable there. Keep finger first but give
    # up after 10s (pam_fprintd's minimum), then fall back to password.
    security.pam.services.polkit-1.rules.auth.fprintd.args = ["timeout=10"];
  };
}
