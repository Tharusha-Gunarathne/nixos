#
# WiFi hotspot with concurrent AP + STA on a single radio.
#
# Usage:
#   sudo start-hotspot                           SSID/password from .env.local
#   sudo start-hotspot -id MyHome                 custom SSID, default password
#   sudo start-hotspot -pw "somepassword1"        default SSID, custom password
#   sudo start-hotspot -id MyHome -pw "pass1234"  custom SSID + password
#   sudo start-hotspot -nopw                      open network, no password
#   sudo start-hotspot -id MyHome -nopw           custom SSID, open network
#   sudo start-hotspot -h                         show usage/help
#   (flags in any order; -pw and -nopw cannot be combined)
#
#   sudo stop-hotspot        stop broadcasting, your WiFi connection is untouched
#   hotspot-status           check whether it's currently active
#   hotspot-clients          list connected devices
#   sudo hotspot-reset       fully remove ap0 (use if it ever gets stuck;
#                            recreated automatically next time wlan0
#                            reconnects, or immediately by start-hotspot)
#
# Requires your normal WiFi connection (interface set in .env.local, e.g.
# wlan0) to already be connected — the hotspot piggybacks its channel.
# Internet from that connection is shared with hotspot clients via NAT.
#
# ap0 is created automatically the moment wlan0 finishes connecting (via a
# NetworkManager dispatcher hook below), not on first start-hotspot call.
# Adding a second virtual interface to the radio for the first time each
# boot causes a brief STA reassociation no matter when it happens — this
# way it happens once, silently, folded into your normal WiFi connection
# at login, rather than surprising you the moment you run start-hotspot.
# Once created, it persists across start/stop cycles within the same boot;
# start/stop only toggle it up/down, never recreate it.
# 
#
{localConfig, ...}: {
  flake.nixosModules.hotspot = {
    pkgs,
    ...
  }: let
    hs        = localConfig.hotspot;
    ssid      = hs.ssid;
    password  = hs.password;
    staIface  = hs.interface;   # your normal WiFi interface, e.g. wlan0
    apIface   = "ap0";          # virtual AP interface

    apGateway   = "10.42.0.1";
    apCidr      = "10.42.0.0/24";
    dhcpStart   = "10.42.0.10";
    dhcpEnd     = "10.42.0.100";

    removeApInterface = pkgs.writeShellScript "remove-ap0" ''
      ${pkgs.iw}/bin/iw dev "${apIface}" del 2>/dev/null || true
    '';

    # Runs on every NetworkManager "up" event. No-ops harmlessly if ap0
    # already exists (the add attempt just fails silently) — the real
    # interface creation, and its one-time blip, happens only the first
    # time wlan0 connects each boot.
    createApOnConnect = pkgs.writeShellScript "hotspot-dispatcher" ''
      #!/bin/sh
      INTERFACE="$1"
      ACTION="$2"
      if [ "$INTERFACE" = "${staIface}" ] && [ "$ACTION" = "up" ]; then
        ${pkgs.iw}/bin/iw dev "${staIface}" interface add "${apIface}" type __ap 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link set "${apIface}" down 2>/dev/null || true
      fi
    '';

    startHotspot = pkgs.writeShellScriptBin "start-hotspot" ''
      set -euo pipefail

      STA="${staIface}"
      AP="${apIface}"

      SSID="${ssid}"
      PASS="${password}"
      PW_SET=0
      NOPW_SET=0

      usage() {
        cat <<'USAGE'
      Usage: start-hotspot [-id <ssid>] [-pw <password> | -nopw]

        -id <ssid>      custom network name (default: from .env.local)
        -pw <password>  custom password, min 8 chars (default: from .env.local)
        -nopw           start an open network, no password
        -h, --help      show this message

      -pw and -nopw cannot be used together.

      Examples:
        start-hotspot
        start-hotspot -id MyHome
        start-hotspot -pw "somepassword1"
        start-hotspot -id MyHome -pw "somepassword1"
        start-hotspot -nopw
        start-hotspot -id MyHome -nopw
      USAGE
      }

      while [ $# -gt 0 ]; do
        case "$1" in
          -h|--help)
            usage
            exit 0
            ;;
          -id)
            if [ $# -lt 2 ]; then
              echo "[hotspot] -id requires a value." >&2
              usage >&2
              exit 1
            fi
            SSID="$2"
            shift 2
            ;;
          -pw)
            if [ $# -lt 2 ]; then
              echo "[hotspot] -pw requires a value." >&2
              usage >&2
              exit 1
            fi
            PASS="$2"
            PW_SET=1
            shift 2
            ;;
          -nopw)
            NOPW_SET=1
            shift
            ;;
          *)
            echo "[hotspot] Unknown argument: $1" >&2
            usage >&2
            exit 1
            ;;
        esac
      done

      if [ "$PW_SET" -eq 1 ] && [ "$NOPW_SET" -eq 1 ]; then
        echo "[hotspot] -pw and -nopw cannot be used together." >&2
        usage >&2
        exit 1
      fi

      if [ "$NOPW_SET" -eq 1 ]; then
        PASS=""
      fi

      if [ -n "$PASS" ] && [ ''${#PASS} -lt 8 ]; then
        echo "[hotspot] Password must be at least 8 characters." >&2
        exit 1
      fi

      FREQ=$(${pkgs.iw}/bin/iw dev "$STA" link | grep -oP 'freq: \K[0-9]+' || true)
      if [ -z "$FREQ" ]; then
        echo "[hotspot] $STA is not connected to WiFi. Connect first, then retry." >&2
        exit 1
      fi

      if [ "$FREQ" -ge 2412 ] && [ "$FREQ" -le 2484 ]; then
        if [ "$FREQ" -eq 2484 ]; then CHANNEL=14; else CHANNEL=$(( (FREQ - 2407) / 5 )); fi
      elif [ "$FREQ" -ge 5000 ]; then
        CHANNEL=$(( (FREQ - 5000) / 5 ))
      else
        echo "[hotspot] Could not map frequency $FREQ to a channel." >&2
        exit 1
      fi
      echo "[hotspot] Piggybacking on $STA's current channel: $CHANNEL ($FREQ MHz)"

      ${pkgs.iw}/bin/iw dev "$STA" interface add "$AP" type __ap 2>/dev/null || true

      # Wait briefly for the interface to actually register — the driver
      # can take a moment right after creation.
      for i in $(seq 1 15); do
        ${pkgs.iproute2}/bin/ip link show "$AP" &>/dev/null && break
        sleep 0.2
      done
      if ! ${pkgs.iproute2}/bin/ip link show "$AP" &>/dev/null; then
        echo "[hotspot] $AP never appeared. Try: sudo hotspot-reset" >&2
        exit 1
      fi

      ${pkgs.iproute2}/bin/ip link set "$AP" up
      ${pkgs.iproute2}/bin/ip addr flush dev "$AP"
      ${pkgs.iproute2}/bin/ip addr add ${apGateway}/24 dev "$AP"

      cat > /run/hostapd-ap0.conf <<EOF
      interface=$AP
      driver=nl80211
      ssid=$SSID
      hw_mode=g
      channel=$CHANNEL
      ieee80211n=1
      macaddr_acl=0
      EOF
      if [ -n "$PASS" ]; then
        cat >> /run/hostapd-ap0.conf <<EOF
      wpa=2
      wpa_passphrase=$PASS
      wpa_key_mgmt=WPA-PSK
      rsn_pairwise=CCMP
      EOF
      else
        echo "auth_algs=1" >> /run/hostapd-ap0.conf
      fi
      ${pkgs.hostapd}/bin/hostapd -B /run/hostapd-ap0.conf -P /run/hostapd-ap0.pid

      ${pkgs.dnsmasq}/bin/dnsmasq \
        --interface="$AP" --bind-interfaces --except-interface=lo \
        --dhcp-range=${dhcpStart},${dhcpEnd},12h \
        --no-resolv --server=1.1.1.1 --server=8.8.8.8 \
        --pid-file=/run/dnsmasq-ap0.pid

      ${pkgs.iptables}/bin/iptables -t nat -A POSTROUTING -s ${apCidr} -o "$STA" -j MASQUERADE
      ${pkgs.iptables}/bin/iptables -A FORWARD -i "$AP" -o "$STA" -j ACCEPT
      ${pkgs.iptables}/bin/iptables -A FORWARD -i "$STA" -o "$AP" -m state --state RELATED,ESTABLISHED -j ACCEPT

      echo "[hotspot] Active. SSID: $SSID  |  Stop with: stop-hotspot"
    '';

    stopHotspot = pkgs.writeShellScriptBin "stop-hotspot" ''
      set -euo pipefail
      STA="${staIface}"
      AP="${apIface}"

      echo "[hotspot] Stopping hotspot..."

      ${pkgs.iptables}/bin/iptables -t nat -D POSTROUTING -s ${apCidr} -o "$STA" -j MASQUERADE 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -D FORWARD -i "$AP" -o "$STA" -j ACCEPT 2>/dev/null || true
      ${pkgs.iptables}/bin/iptables -D FORWARD -i "$STA" -o "$AP" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || true

      if [ -f /run/dnsmasq-ap0.pid ]; then
        kill "$(cat /run/dnsmasq-ap0.pid)" 2>/dev/null || true
        rm -f /run/dnsmasq-ap0.pid
      fi
      if [ -f /run/hostapd-ap0.pid ]; then
        kill "$(cat /run/hostapd-ap0.pid)" 2>/dev/null || true
        rm -f /run/hostapd-ap0.pid
      fi

      ${pkgs.iproute2}/bin/ip addr flush dev "$AP" 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link set "$AP" down 2>/dev/null || true

      echo "[hotspot] Hotspot stopped. $STA's connection is untouched."
    '';

    hotspotStatus = pkgs.writeShellScriptBin "hotspot-status" ''
      AP="${apIface}"
      if ${pkgs.iproute2}/bin/ip link show "$AP" | grep -q "state UP"; then
        echo "[hotspot] Active. SSID: ${ssid}"
        ${pkgs.iproute2}/bin/ip -4 addr show dev "$AP" | grep inet || true
      else
        echo "[hotspot] Not active."
      fi
    '';

    hotspotClients = pkgs.writeShellScriptBin "hotspot-clients" ''
      echo "[hotspot] Clients on ${apIface}:"
      ${pkgs.iproute2}/bin/ip neigh show dev "${apIface}" 2>/dev/null \
        | grep -v FAILED \
        || echo "  (none yet, or hotspot not active)"
    '';

    hotspotReset = pkgs.writeShellScriptBin "hotspot-reset" ''
      set -euo pipefail
      echo "[hotspot] Resetting ${apIface} (stop and remove)..."
      ${stopHotspot}/bin/stop-hotspot || true
      ${removeApInterface}
      echo "[hotspot] Done. ${apIface} will be recreated automatically next"
      echo "time ${staIface} reconnects, or run start-hotspot now to recreate it immediately."
    '';

  in {
    environment.systemPackages = [
      pkgs.iw
      pkgs.hostapd
      pkgs.dnsmasq
      pkgs.iptables
      startHotspot
      stopHotspot
      hotspotStatus
      hotspotClients
      hotspotReset
    ];

    networking.networkmanager.unmanaged = ["interface-name:${apIface}"];
    networking.firewall.trustedInterfaces = [apIface];
    networking.networkmanager.dispatcherScripts = [
      {
        source = createApOnConnect;
        type = "basic";
      }
    ];

    # net.ipv4.ip_forward is already set to 1 by tailscale.nix.
  };
}