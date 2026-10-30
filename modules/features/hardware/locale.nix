{localConfig, ...}: {
  flake.nixosModules.locale = {...}: {
    time.timeZone = (localConfig.locale or {}).time_zone or "UTC";
    i18n.defaultLocale = "en_US.UTF-8";
  };
}
