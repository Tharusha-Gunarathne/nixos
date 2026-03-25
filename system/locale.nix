# System timezone and default locale configuration.
{ config, lib, pkgs, username, ... }:

{
  time.timeZone = "Asia/Colombo";
  i18n.defaultLocale = "en_US.UTF-8";
}
