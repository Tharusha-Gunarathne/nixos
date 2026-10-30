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
    config,
    lib,
    pkgs,
    ...
  }: let
    hs        = localConfig.hotspot;
    ssid      = hs.ssid;
    readPassword = "${pkgs.python3}/bin/python3 ${../core/local-value.py} ${lib.escapeShellArg "${config.myConfig.repoRoot}/.env.local"} hotspot password";
    staIface  = hs.interface;   # your normal WiFi interface, e.g. wlan0
    apIface   = "ap0";          # virtual AP interface

    # Account granted passwordless start/stop, so the Noctalia plugin can
    # toggle the hotspot without a prompt.
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
      PASS="$(${readPassword})"
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

      # An open network must always be an explicit choice. Silently falling
      # back to a blank password from .env.local would broadcast an
      # unencrypted AP on a plain `start-hotspot`.
      if [ "$NOPW_SET" -eq 0 ] && [ -z "$PASS" ]; then
        echo "[hotspot] No password configured. Set password under [hotspot] in .env.local, or pass -pw <password>, or pass -nopw to deliberately start an open network." >&2
        exit 1
      fi

      if [ -n "$PASS" ] && [ ''${#PASS} -lt 8 ]; then
        echo "[hotspot] Password must be at least 8 characters." >&2
        exit 1
      fi

      # SSID and password land verbatim in the hostapd config below, and this
      # script is reachable through passwordless sudo, so reject anything that
      # could break out of its line and inject a directive.
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

      # Refuse to stack a second instance on a live one. Deliberately does not
      # touch $AP: per the design note at the top of this file, start/stop only
      # toggle the interface up/down and never recreate it.
      if [ -f /run/hostapd-ap0.pid ] && [ -d "/proc/$(cat /run/hostapd-ap0.pid 2>/dev/null)" ]; then
        echo "[hotspot] Already running. Stop it first with: stop-hotspot" >&2
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

      # Clear any leftover state from a crashed session before bringing the
      # interface up. This is a down/flush only -- never a delete and re-add,
      # which would trigger the STA reassociation blip the dispatcher-hook
      # design exists to avoid, and drop your WiFi every time you start.
      ${pkgs.iproute2}/bin/ip link set "$AP" down 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip addr flush dev "$AP" 2>/dev/null || true

      ${pkgs.iproute2}/bin/ip link set "$AP" up
      ${pkgs.iproute2}/bin/ip addr flush dev "$AP"
      ${pkgs.iproute2}/bin/ip addr add ${apGateway}/24 dev "$AP"

      mkdir -p /run/hostapd
      cat > /run/hostapd-ap0.conf <<EOF
      interface=$AP
      driver=nl80211
      ssid=$SSID
      hw_mode=g
      channel=$CHANNEL
      ieee80211n=1
      macaddr_acl=0
      ctrl_interface=/run/hostapd
      ctrl_interface_group=0
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

      # The conf holds wpa_passphrase in clear text and /run is world-readable,
      # so keep it root-only. Everything the unprivileged status command needs
      # goes into a separate public file that deliberately excludes the key.
      chmod 600 /run/hostapd-ap0.conf
      if [ -n "$PASS" ]; then SECURED=yes; else SECURED=no; fi
      printf 'ssid=%s\nchannel=%s\nsecured=%s\n' "$SSID" "$CHANNEL" "$SECURED" > /run/hotspot-ap0.info
      chmod 644 /run/hotspot-ap0.info
      ${pkgs.hostapd}/bin/hostapd -B /run/hostapd-ap0.conf -P /run/hostapd-ap0.pid

      # `hostapd -B` forks and the parent exits 0 immediately, so `set -e`
      # cannot catch a child that dies a moment later during driver setup.
      # Without this the script would continue, start dnsmasq, add the NAT
      # rules and exit 0 with no AP running -- reporting success while the
      # hotspot is dead. Teardown here mirrors stop-hotspot: down and flush
      # only, never a delete.
      sleep 1
      if [ ! -f /run/hostapd-ap0.pid ] || [ ! -d "/proc/$(cat /run/hostapd-ap0.pid 2>/dev/null)" ]; then
        echo "[hotspot] hostapd exited during startup on channel $CHANNEL." >&2
        echo "[hotspot] To see why, run it in the foreground:" >&2
        echo "[hotspot]   sudo ${pkgs.hostapd}/bin/hostapd /run/hostapd-ap0.conf" >&2
        rm -f /run/hostapd-ap0.pid
        ${pkgs.iproute2}/bin/ip addr flush dev "$AP" 2>/dev/null || true
        ${pkgs.iproute2}/bin/ip link set "$AP" down 2>/dev/null || true
        exit 1
      fi

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
      rm -f /run/hotspot-ap0.info /run/hostapd-ap0.conf

      ${pkgs.iproute2}/bin/ip addr flush dev "$AP" 2>/dev/null || true
      ${pkgs.iproute2}/bin/ip link set "$AP" down 2>/dev/null || true

      echo "[hotspot] Hotspot stopped. $STA's connection is untouched."
    '';

    # Two flavours:
    #   hotspot-status           human-readable
    #   hotspot-status --json    machine-readable snapshot for the Noctalia plugin
    #
    # Deliberately unprivileged: the plugin polls this every few seconds and
    # nothing here needs root. `iw station dump` is attempted but allowed to
    # fail, in which case per-client signal strength is simply absent.
    #
    # Activity is judged by a live hostapd process, not by `ip link ... state
    # UP`. ap0 is created and left present for the whole boot by the dispatcher
    # hook, so its mere existence says nothing about whether the AP is running.
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
          -h|--help) echo "Usage: hotspot-status [--json] [--ap <iface>] [--sta <iface>]"; exit 0 ;;
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

      # `kill -0 <pid>` fails with EPERM when an unprivileged user probes a
      # root-owned process, so it reports a running hostapd as dead. That is
      # why `hotspot-status` said "not active" without sudo, and why the
      # plugin's unprivileged poll always showed the hotspot off. /proc is
      # world-readable, so test there instead, and compare comm to guard
      # against PID reuse.
      pid_alive() {
        p="''${1:-}"
        case "$p" in (""|*[!0-9]*) return 1 ;; esac
        [ -d "/proc/$p" ] || return 1
        read -r c < "/proc/$p/comm" 2>/dev/null || return 0
        [ "$c" = "''${2:-hostapd}" ]
      }

      ACTIVE=false
      if [ -f /run/hostapd-ap0.pid ] && pid_alive "$(cat /run/hostapd-ap0.pid 2>/dev/null)" hostapd; then
        ACTIVE=true
      fi

      # Read the public info file, not the root-only conf.
      AP_SSID=""
      AP_CHANNEL=0
      SECURED=no
      if [ "$ACTIVE" = true ] && [ -f /run/hotspot-ap0.info ]; then
        AP_SSID=$(sed -n 's/^ssid=//p' /run/hotspot-ap0.info | head -n1)
        AP_CHANNEL=$(sed -n 's/^channel=//p' /run/hotspot-ap0.info | head -n1)
        SECURED=$(sed -n 's/^secured=//p' /run/hotspot-ap0.info | head -n1)
      fi
      case "$AP_CHANNEL" in (""|*[!0-9]*) AP_CHANNEL=0 ;; esac
      case "$SECURED" in (yes) SECURED=true ;; (*) SECURED=false ;; esac

      GATEWAY=$(${pkgs.iproute2}/bin/ip -4 -o addr show dev "$AP" 2>/dev/null \
        | ${pkgs.gawk}/bin/awk '{print $4}' | cut -d/ -f1 | head -n1)

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

      # ip neigh gives IPs, iw station dump gives MACs + signal. Merge on MAC
      # so a station that has associated but not yet taken a lease still shows.
      CLIENTS='[]'
      if [ "$ACTIVE" = true ]; then
        NEIGH=$(${pkgs.iproute2}/bin/ip -4 neigh show dev "$AP" 2>/dev/null | grep -v -e FAILED -e INCOMPLETE || true)

        # Association state is the only reliable "is it still here" signal.
        # ARP entries linger as STALE for minutes after a device disconnects,
        # so a neighbour entry alone must never create a client row.
        # `iw station dump` needs CAP_NET_ADMIN on some drivers; when the
        # unprivileged read fails we retry through a NOPASSWD helper, and only
        # if both fail do we degrade to the (stale-prone) neighbour list.
        STATIONS_OK=1
        if ! STATIONS=$(${pkgs.iw}/bin/iw dev "$AP" station dump 2>/dev/null); then
          if ! STATIONS=$(sudo -n hotspot-stations "$AP" 2>/dev/null); then
            STATIONS=""
            STATIONS_OK=0
          fi
        fi

        CLIENTS=$( {
            printf '%s\n' "$STATIONS" | sed 's/^/S /'
            printf '%s\n' "$NEIGH"    | sed 's/^/N /'
          } | ${pkgs.gawk}/bin/awk -v stations_ok="$STATIONS_OK" '
              $1=="S" && $2=="Station" { mac=tolower($3); assoc[mac]=1 }
              $1=="S" && $2=="signal:" { if (mac != "") sig[mac]=$3 }
              $1=="N" && $3=="lladdr"  { m=tolower($4); ip[m]=$2; neigh[m]=1 }
              END {
                if (stations_ok == "1") { for (m in assoc) show[m]=1 }
                else                    { for (m in neigh) show[m]=1 }
                for (m in show)
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
          --argjson secured "$SECURED" \
          --arg     default_ssid "${ssid}" \
          '{
             available: $available,
             active: $active,
             ssid: $ssid,
             ap_interface: $ap_interface,
             sta_interface: $sta_interface,
             channel: $channel,
             secured: $secured,
             default_ssid: $default_ssid,
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

    # Privileged station dump, used only when the unprivileged `iw` read is
    # refused by the driver. Read-only.
    hotspotStations = pkgs.writeShellScriptBin "hotspot-stations" ''
      set -o pipefail
      AP="''${1:-${apIface}}"
      case "$AP" in (*[!a-zA-Z0-9_-]*) echo "hotspot-stations: bad interface" >&2; exit 1 ;; esac
      ${pkgs.iw}/bin/iw dev "$AP" station dump
    '';

    # Deauthenticate one associated client. hostapd has no persistent ban here,
    # so a device may simply reconnect -- this drops the current session, it is
    # not a block list.
    hotspotKick = pkgs.writeShellScriptBin "hotspot-kick" ''
      set -o pipefail
      MAC="''${1:-}"
      H="[0-9a-fA-F][0-9a-fA-F]"
      # Reachable through passwordless sudo, so validate strictly rather than
      # handing an arbitrary string to hostapd_cli.
      case "$MAC" in
        $H:$H:$H:$H:$H:$H) : ;;
        *) echo "hotspot-kick: expected a MAC address, got: $MAC" >&2; exit 1 ;;
      esac
      if [ ! -S /run/hostapd/${apIface} ]; then
        echo "hotspot-kick: hostapd control socket not found; is the hotspot running?" >&2
        exit 1
      fi
      ${pkgs.hostapd}/bin/hostapd_cli -p /run/hostapd -i ${apIface} deauthenticate "$MAC"
    '';

    # Prints the passphrase of the running hotspot, nothing else. The conf is
    # root-only (chmod 600 above), so this needs sudo -- it is the one privileged
    # read the plugin makes, and only when the user taps "reveal". Deliberately
    # a separate command rather than a field in hotspot-status, so the key never
    # rides along on the unprivileged status poll.
    hotspotSecret = pkgs.writeShellScriptBin "hotspot-secret" ''
      set -o pipefail
      # --default prints the password configured in .env.local (what a start
      # with no override would use); with no flag, the passphrase of the
      # hotspot currently running.
      if [ "''${1:-}" = "--default" ]; then
        ${readPassword}
        printf '\n'
        exit 0
      fi
      CONF=/run/hostapd-ap0.conf
      [ -f "$CONF" ] || exit 0
      sed -n 's/^wpa_passphrase=//p' "$CONF" | head -n1
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
      hotspotSecret
      hotspotStations
      hotspotKick
    ];

    # The Noctalia plugin drives the hotspot with `sudo -n`, so these three
    # need to be passwordless. hotspot-status is deliberately absent: it is
    # read-only and unprivileged, so the poll loop never touches sudo.
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
            "/run/current-system/sw/bin/hotspot-secret"
            "/run/current-system/sw/bin/hotspot-stations"
            "/run/current-system/sw/bin/hotspot-kick"
            "${startHotspot}/bin/start-hotspot"
            "${stopHotspot}/bin/stop-hotspot"
            "${hotspotReset}/bin/hotspot-reset"
            "${hotspotSecret}/bin/hotspot-secret"
            "${hotspotStations}/bin/hotspot-stations"
            "${hotspotKick}/bin/hotspot-kick"
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
