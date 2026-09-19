{...}: {
  flake.nixosModules.journald = {...}: {
    # Cap persistent journal size so logs can't silently eat the root disk.
    services.journald.settings.Journal = {
      SystemMaxUse = "200M";
      SystemMaxFileSize = "50M";
      MaxRetentionSec = "1month";
    };
  };
}
