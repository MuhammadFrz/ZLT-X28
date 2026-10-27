#!/bin/sh
set -eu
umask 077
base=/data/home-ikev2/full-review
test -f "$base/armed" || exit 0
if [ -f "$base/fixture-owned" ]; then
 iptables -w 3 -t nat -D PREROUTING -i br0 -s 192.168.70.107 -d 192.168.70.1 -p tcp --dport 18444 -j X28_IKE_REVIEW 2>/dev/null || true
 for protocol in udp tcp;do
  iptables -w 3 -t nat -D PREROUTING -i br0 -s 192.168.70.107 -d 192.168.70.1 -p "$protocol" --dport 15355 -j X28_IKE_REVIEW 2>/dev/null || true
  conntrack -D -s 192.168.70.107 -d 192.168.70.1 -p "$protocol" --dport 15355 >/dev/null 2>&1 || true
 done
 iptables -w 3 -t nat -F X28_IKE_REVIEW 2>/dev/null || true
 iptables -w 3 -t nat -X X28_IKE_REVIEW 2>/dev/null || true
 conntrack -D -s 192.168.70.107 -d 192.168.70.1 -p tcp --dport 18444 >/dev/null 2>&1 || true
fi
success=0
for i in 1 2 3 4 5; do
 if /usr/libexec/home-ikev2-control disable >"$base/cleanup.log" 2>&1; then success=1;break;fi
 sleep 2
done
test "$success" = 1
test ! -f /data/home-ikev2/enabled
test ! -f /data/home-ikev2/routing-owned
lua - <<'RESTORE'
local fs=require 'nixio.fs'
local previous=tonumber(fs.readfile('/data/home-ikev2/full-review/previous-selection') or '')
if previous then assert(require('luci.model.home_ikev2').select(previous)) end
RESTORE
rm -f "$base/armed" "$base/fixture-owned"
rm -f /data/home-ikev2/boot-review/armed
printf 'completed\n' >"$base/cleanup-status"
