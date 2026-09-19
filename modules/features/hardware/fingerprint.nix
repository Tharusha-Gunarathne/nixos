{...}: {
  flake.nixosModules.fingerprint = {...}: {
    # Goodix 27c6:659a (goodixmoc driver) -- supported by stock libfprint.
    # Enroll with `fprintd-enroll`, verify with `fprintd-verify`.
    services.fprintd.enable = true;

    # fprintd adds pam_fprintd to every PAM service. Keep the greeter on
    # password only: a fingerprint login can't unlock gnome-keyring, and
    # pam_fprintd would sit in front of the password prompt at boot.
    # The Noctalia lock screen uses the "login" stack but strips
    # pam_fprintd and drives fprintd over D-Bus itself, so it's unaffected.
    # sudo and polkit keep fingerprint.
    security.pam.services.greetd.fprintAuth = false;
  };
}
