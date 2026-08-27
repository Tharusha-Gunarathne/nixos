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
#   An open network is never implicit: if [hotspot].password in .env.local is
#   empty and neither -pw nor -nopw is passed, start-hotspot refuses rather
#   than quietly broadcasting without encryption.
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

    # Account granted passwordless start/stop, so the Noctalia plugin can
    # toggle the hotspot without a prompt. Reuses [user].username from
    # .env.local rather than introducing a hotspot-specific key.
    hotspotUser = localConfig.user.username;

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
      An open network is never the default: if no password is set in
      .env.local and neither -pw nor -nopw is given, this exits with an error.

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

      # An open network must always be an explicit choice. Silently falling
      # back to a blank password from .env.local would broadcast an
      # unencrypted AP on a plain `start-hotspot`, so refuse and make the
      # caller say so with -nopw.
      if [ "$NOPW_SET" -eq 0 ] && [ -z "$PASS" ]; then
        echo "[hotspot] No password configured. Set password under [hotspot] in .env.local, or pass -pw <password>, or pass -nopw to deliberately start an open network." >&2
        exit 1
      fi

      if [ -n "$PASS" ] && [ ''${#PASS} -lt 8 ]; then
        echo "[hotspot] Password must be at least 8 characters." >&2
        exit 1
      fi

      # These land verbatim in the hostapd config below, and this script is
      # reachable through passwordless sudo, so reject anything that could
      # break out of its line and inject a directive.
      case "$SSID" in
        "" ) echo "[hotspot] SSID must not be empty." >&2; exit 1 ;;
        *[![:print:]]* ) echo "[hotspot] SSID contains non-printable characters." >&2; exit 1 ;;
      esac
      if [ ''${#SSID} -gt 32 ]; then
        echo "[hotspot] SSID must be at most 32 characters." >&2
        exit 1
      fi
      case "$PASS" in
        *[![:print:]]* ) echo "[hotspot] Password contains non-printable characters." >&2; exit 1 ;;
      esac
      if [ -n "$PASS" ] && [ ''${#PASS} -gt 63 ]; then
        echo "[hotspot] Password must be at most 63 characters." >&2
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

      cat > /run/hostapd-$AP.conf <<EOF
      interface=$AP
      driver=nl80211
      ssid=$SSID
      hw_mode=g
      channel=$CHANNEL
      ieee80211n=1
      macaddr_acl=0
      EOF
      if [ -n "$PASS" ]; then
        cat >> /run/hostapd-$AP.conf <<EOF
      wpa=2
      wpa_passphrase=$PASS
      wpa_key_mgmt=WPA-PSK
      rsn_pairwise=CCMP
      EOF
      else
        echo "auth_algs=1" >> /run/hostapd-$AP.conf
      fi
      ${pkgs.hostapd}/bin/hostapd -B /run/hostapd-$AP.conf -P /run/hostapd-$AP.pid

      ${pkgs.dnsmasq}/bin/dnsmasq \
        --interface="$AP" --bind-interfaces --except-interface=lo \
        --dhcp-range=${dhcpStart},${dhcpEnd},12h \
        --no-resolv --server=1.1.1.1 --server=8.8.8.8 \
        --pid-file=/run/dnsmasq-$AP.pid

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

      if [ -f /run/dnsmasq-$AP.pid ]; then
        kill "$(cat /run/dnsmasq-$AP.pid)" 2>/dev/null || true
        rm -f /run/dnsmasq-$AP.pid
      fi
      if [ -f /run/hostapd-$AP.pid ]; then
        kill "$(cat /run/hostapd-$AP.pid)" 2>/dev/null || true
        rm -f /run/hostapd-$AP.pid
      fi

      ${pkgs.iproute2}/bin/ip addr flush dev "$AP" 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link set "$AP" down 2>/dev/null || true

      echo "[hotspot] Hotspot stopped. $STA's connection is untouched."
    '';

    # Single source of truth for hotspot state, in two flavours:
    #   hotspot-status           human-readable, unchanged behaviour
    #   hotspot-status --json    machine-readable snapshot for the Noctalia plugin
    #
    # Deliberately unprivileged: the Noctalia service polls this every few
    # seconds, and nothing here needs root. `iw station dump` is attempted but
    # allowed to fail, in which case per-client signal strength is simply absent.
    hotspotStatus = pkgs.writeShellScriptBin "hotspot-status" ''
      set -o pipefail

      AP="${apIface}"
      STA="${staIface}"
      JSON=0

      while [ $# -gt 0 ]; do
        case "$1" in
          --json) JSON=1; shift ;;
          --ap)   [ $# -ge 2 ] || { echo "hotspot-status: --ap requires a value" >&2; exit 1; }; AP="$2"; shift 2 ;;
          --sta)  [ $# -ge 2 ] || { echo "hotspot-status: --sta requires a value" >&2; exit 1; }; STA="$2"; shift 2 ;;
          -h|--help)
            echo "Usage: hotspot-status [--json] [--ap <iface>] [--sta <iface>]"
            exit 0 ;;
          *) echo "hotspot-status: unknown argument: $1" >&2; exit 1 ;;
        esac
      done

      freq_to_channel() {
        f="''${1:-}"
        case "$f" in (""|*[!0-9]*) echo 0; return ;; esac
        if [ "$f" -eq 2484 ]; then echo 14
        elif [ "$f" -ge 2412 ] && [ "$f" -le 2472 ]; then echo $(( (f - 2407) / 5 ))
        elif [ "$f" -ge 5000 ]; then echo $(( (f - 5000) / 5 ))
        else echo 0
        fi
      }

      # --- access point -------------------------------------------------
      ACTIVE=false
      PIDFILE="/run/hostapd-$AP.pid"
      CONFFILE="/run/hostapd-$AP.conf"
      if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null; then
        ACTIVE=true
      fi

      AP_SSID=""
      AP_CHANNEL=0
      if [ "$ACTIVE" = true ] && [ -f "$CONFFILE" ]; then
        AP_SSID=$(sed -n 's/^ssid=//p' "$CONFFILE" | head -n1)
        AP_CHANNEL=$(sed -n 's/^channel=//p' "$CONFFILE" | head -n1)
      fi
      case "$AP_CHANNEL" in (""|*[!0-9]*) AP_CHANNEL=0 ;; esac

      GATEWAY=$(${pkgs.iproute2}/bin/ip -4 -o addr show dev "$AP" 2>/dev/null \
        | ${pkgs.gawk}/bin/awk '{print $4}' | cut -d/ -f1 | head -n1)

      # --- uplink (the STA whose channel the AP borrows) ----------------
      UP_CONNECTED=false
      UP_SSID=""
      UP_CHANNEL=0
      LINK=$(${pkgs.iw}/bin/iw dev "$STA" link 2>/dev/null || true)
      if [ -n "$LINK" ] && ! printf '%s\n' "$LINK" | grep -qi '^Not connected'; then
        UP_CONNECTED=true
        UP_SSID=$(printf '%s\n' "$LINK" | sed -n 's/^[[:space:]]*SSID: //p' | head -n1)
        UP_FREQ=$(printf '%s\n' "$LINK" | sed -n 's/^[[:space:]]*freq: //p' | head -n1 | ${pkgs.gawk}/bin/awk '{print $1}')
        UP_CHANNEL=$(freq_to_channel "''${UP_FREQ:-}")
      fi

      # --- connected clients --------------------------------------------
      # ip neigh gives IPs, iw station dump gives MACs + signal. Merge on MAC
      # so a station that has associated but not yet taken a lease still shows.
      CLIENTS='[]'
      if [ "$ACTIVE" = true ]; then
        NEIGH=$(${pkgs.iproute2}/bin/ip -4 neigh show dev "$AP" 2>/dev/null | grep -v -e FAILED -e INCOMPLETE || true)
        STATIONS=$(${pkgs.iw}/bin/iw dev "$AP" station dump 2>/dev/null || true)
        CLIENTS=$( {
            printf '%s\n' "$STATIONS" | sed 's/^/S /'
            printf '%s\n' "$NEIGH"    | sed 's/^/N /'
          } | ${pkgs.gawk}/bin/awk '
              $1=="S" && $2=="Station" { mac=tolower($3); seen[mac]=1 }
              $1=="S" && $2=="signal:" { if (mac != "") sig[mac]=$3 }
              $1=="N" && $3=="lladdr"  { m=tolower($4); ip[m]=$2; seen[m]=1 }
              END {
                for (m in seen)
                  printf "%s\t%s\t%s\n", m, (m in ip ? ip[m] : ""), (m in sig ? sig[m] : "")
              }
            ' | ${pkgs.jq}/bin/jq -R -s '
              split("\n") | map(select(length > 0) | split("\t") | {
                mac:    .[0],
                ip:     .[1],
                signal: (if .[2] == "" then null else (.[2] | tonumber? // null) end)
              })')
        case "$CLIENTS" in ("") CLIENTS='[]' ;; esac
      fi

      if [ "$JSON" -eq 1 ]; then
        ${pkgs.jq}/bin/jq -n \
          --argjson available true \
          --argjson active "$ACTIVE" \
          --arg     ssid "$AP_SSID" \
          --arg     ap_interface "$AP" \
          --arg     sta_interface "$STA" \
          --argjson channel "$AP_CHANNEL" \
          --arg     gateway "''${GATEWAY:-}" \
          --argjson up_connected "$UP_CONNECTED" \
          --arg     up_ssid "$UP_SSID" \
          --argjson up_channel "$UP_CHANNEL" \
          --argjson clients "$CLIENTS" \
          '{
             available: $available,
             active: $active,
             ssid: $ssid,
             ap_interface: $ap_interface,
             sta_interface: $sta_interface,
             channel: $channel,
             gateway: $gateway,
             uplink: { connected: $up_connected, ssid: $up_ssid, channel: $up_channel },
             clients: $clients,
             error: ""
           }'
        exit 0
      fi

      if [ "$ACTIVE" = true ]; then
        echo "[hotspot] Active. SSID: ''${AP_SSID:-${ssid}}  |  channel: $AP_CHANNEL"
        [ -n "''${GATEWAY:-}" ] && echo "[hotspot] Gateway: $GATEWAY"
        echo "[hotspot] Clients: $(printf '%s' "$CLIENTS" | ${pkgs.jq}/bin/jq 'length')"
      else
        echo "[hotspot] Not active."
      fi
      if [ "$UP_CONNECTED" = true ]; then
        echo "[hotspot] Uplink: $UP_SSID on $STA (channel $UP_CHANNEL)"
      else
        echo "[hotspot] Uplink: $STA is not connected."
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

    # The Noctalia plugin drives the hotspot with `sudo -n`, so these three
    # need to be passwordless. Everything else still prompts as usual.
    # hotspot-status is deliberately absent: it is read-only and unprivileged.
    security.sudo.extraRules = [
      {
        users = [hotspotUser];
        commands = let
          # Both paths are listed because sudo matches the command as resolved
          # through secure_path, which is the /run/current-system symlink.
          paths = [
            "/run/current-system/sw/bin/start-hotspot"
            "/run/current-system/sw/bin/stop-hotspot"
            "/run/current-system/sw/bin/hotspot-reset"
            "${startHotspot}/bin/start-hotspot"
            "${stopHotspot}/bin/stop-hotspot"
            "${hotspotReset}/bin/hotspot-reset"
          ];
        in
          map (command: {
            inherit command;
            options = ["NOPASSWD" "SETENV"];
          })
          paths;
      }
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