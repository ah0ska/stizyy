#!/bin/bash
SRV="$1"; APP_PID="$2"; STOP="$3"; RES="$4"
DEV=utun123; TIP=198.18.0.1
GW=$(route -n get default | awk '/gateway:/{print $2}')
[ -z "$GW" ] && { echo "нет шлюза по умолчанию"; exit 1; }
IFS=',' read -ra IPS <<< "$SRV"
svcs() { networksetup -listallnetworkservices | tail -n +2 | grep -v '^\*'; }
cleanup() {
  for ip in "${IPS[@]}"; do route -n delete -host "$ip" >/dev/null 2>&1; done
  route -n delete -net 0.0.0.0/1 >/dev/null 2>&1
  route -n delete -net 128.0.0.0/1 >/dev/null 2>&1
  [ -n "$T2S" ] && kill "$T2S" 2>/dev/null
  svcs | while IFS= read -r s; do networksetup -setdnsservers "$s" empty; done
  dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
  rm -f "$STOP"
}
trap cleanup EXIT
trap 'exit 0' TERM INT
"$RES/tun2socks" -device "tun://$DEV" -proxy socks5://127.0.0.1:10808 -loglevel warn &
T2S=$!
sleep 1.5
ifconfig $DEV inet $TIP $TIP up
for ip in "${IPS[@]}"; do route -n add -host "$ip" "$GW"; done
route -n add -net 0.0.0.0/1 $TIP
route -n add -net 128.0.0.0/1 $TIP
svcs | while IFS= read -r s; do networksetup -setdnsservers "$s" 1.1.1.1 8.8.8.8; done
dscacheutil -flushcache; killall -HUP mDNSResponder 2>/dev/null
while kill -0 "$APP_PID" 2>/dev/null && kill -0 "$T2S" 2>/dev/null && [ ! -e "$STOP" ]; do sleep 1; done
