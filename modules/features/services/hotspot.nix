{localConfig, ...}: {
  flake.nixosModules.hotspot = {
    pkgs,
    lib,
    ...
  }: let
    hs        = localConfig.hotspot;
    ssid      = hs.ssid;
    password  = hs.password;
    interface = hs.interface;
    band      = hs.band;

    hasPassword = password != "";

    # nmcli creates a connection named "Hotspot" by default.
    # Using `device wifi hotspot` is transient — it goes away on disconnect or reboot,
    # which is exactly what "start when needed" calls for.
    startHotspot = pkgs.writeShellScriptBin "start-hotspot" ''
      set -euo pipefail

      # Kill any stale Hotspot connection first so nmcli doesn't complain
      ${pkgs.networkmanager}/bin/nmcli connection delete Hotspot 2>/dev/null || true

      echo "[hotspot] Starting hotspot on ${interface} (SSID: ${ssid}, band: ${band})..."

      ${pkgs.networkmanager}/bin/nmcli device wifi hotspot \
        ifname   "${interface}" \
        ssid     "${ssid}" \
        ${lib.optionalString hasPassword ''password  "${password}" \''}
        band     "${band}"

      echo "[hotspot] Active. Stop with: stop-hotspot"
      echo "[hotspot] Status:            hotspot-status"
    '';

    stopHotspot = pkgs.writeShellScriptBin "stop-hotspot" ''
      set -euo pipefail
      echo "[hotspot] Stopping hotspot..."
      ${pkgs.networkmanager}/bin/nmcli connection down   Hotspot 2>/dev/null || true
      ${pkgs.networkmanager}/bin/nmcli connection delete Hotspot 2>/dev/null || true
      echo "[hotspot] Hotspot stopped."
    '';

    hotspotStatus = pkgs.writeShellScriptBin "hotspot-status" ''
      ACTIVE=$(${pkgs.networkmanager}/bin/nmcli -t -f NAME,TYPE,STATE connection show --active \
        | grep ":802-11-wireless:" || true)

      if [ -n "$ACTIVE" ]; then
        echo "[hotspot] Active connections:"
        echo "$ACTIVE"
        echo ""
        ${pkgs.networkmanager}/bin/nmcli device show "${interface}" \
          | grep -E "GENERAL\.(DEVICE|STATE)|IP4\.(ADDRESS|GATEWAY)" || true
      else
        echo "[hotspot] No active WiFi connections (hotspot is off)."
      fi
    '';

    # Show connected clients via ARP table — works once hotspot is up
    hotspotClients = pkgs.writeShellScriptBin "hotspot-clients" ''
      echo "[hotspot] Clients on ${interface}:"
      ${pkgs.iproute2}/bin/ip neigh show dev "${interface}" 2>/dev/null \
        | grep -v FAILED \
        || echo "  (none yet, or interface not up)"
    '';

  in {
    environment.systemPackages = [
      startHotspot
      stopHotspot
      hotspotStatus
      hotspotClients
    ];
  };
}