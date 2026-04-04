{self, ...}: {
  flake.nixosModules.locale = {...}: {
    time.timeZone = "Asia/Colombo";
    i18n.defaultLocale = "en_US.UTF-8";
  };
}
