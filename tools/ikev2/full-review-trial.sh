#!/bin/sh
set -eu
umask 077
test "${1:-}" = authorized-full-lan-trial
base=/data/home-ikev2/full-review
control=/usr/libexec/home-ikev2-control
test ! -f /data/home-tunnel/enabled
test ! -f /data/home-ikev2/enabled
test ! -f /data/home-ikev2/routing-owned
test ! -f "$base/armed"
if netstat -lnut | grep -Eq ':(18444|15355)[[:space:]]';then exit 1;fi
mkdir -p "$base";chmod 700 "$base"
rm -f "$base/cleanup-status" "$base/previous-selection" "$base/exit-code" "$base/status"
for name in test-loss test-recovery test-crash finish abort; do rm -f "$base/$name";done
touch "$base/armed"
sh "$base/watchdog.sh" >"$base/watchdog.log" 2>&1 &
watchdog=$!
printf '%s\n' "$watchdog" >"$base/watchdog.pid"
cleanup() {
 code=$?
 trap - EXIT INT TERM HUP
 if sh "$base/cleanup.sh"; then kill "$watchdog" 2>/dev/null || true;else code=1;fi
 printf '%s\n' "$code" >"$base/exit-code"
 exit "$code"
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
lua - <<'SELECT'
local fs=require 'nixio.fs'
local m=require 'luci.model.home_ikev2'
local s=m.summary()
local choice
for _,p in ipairs(s.profiles) do
 if p.server=='45.136.155.55' and p.identity=='tr-ist.prod.surfshark.com' then choice=p.index;break end
end
assert(choice,'The verified Turkey IP profile is required')
assert(fs.writefile('/data/home-ikev2/full-review/previous-selection',tostring(s.selected)))
assert(m.select(choice))
SELECT
"$control" trial >"$base/start.log" 2>&1
touch "$base/fixture-owned"
iptables -w 3 -t nat -N X28_IKE_REVIEW
iptables -w 3 -t nat -A X28_IKE_REVIEW -p tcp --dport 18444 -j DNAT --to-destination 1.1.1.1:443
for protocol in udp tcp;do
 iptables -w 3 -t nat -A X28_IKE_REVIEW -p "$protocol" --dport 15355 -j DNAT --to-destination 8.8.8.8:53
 iptables -w 3 -t nat -I PREROUTING 1 -i br0 -s 192.168.70.107 -d 192.168.70.1 -p "$protocol" --dport 15355 -j X28_IKE_REVIEW
done
iptables -w 3 -t nat -I PREROUTING 1 -i br0 -s 192.168.70.107 -d 192.168.70.1 -p tcp --dport 18444 -j X28_IKE_REVIEW
ready() {
 for i in $(seq 1 60); do
  test ! -f "$base/abort"
  if lua -e 'os.exit(require("luci.model.home_ikev2").summary().running and 0 or 1)'; then return 0;fi
  sleep 1
 done
 return 1
}
await() {
 for i in $(seq 1 45); do
  test ! -f "$base/abort"
  test -f "$base/$1" && return 0
  sleep 1
 done
 return 1
}
ready
printf 'ready\n' >"$base/status"
await test-loss
/etc/init.d/home-ikev2 stop
"$control" stop-daemon
"$control" detach
printf 'loss-ready\n' >"$base/status"
await test-recovery
/etc/init.d/home-ikev2 start
ready
printf 'recovered\n' >"$base/status"
await test-crash
pid=$(cat /data/home-ikev2/control/daemon.pid)
case "$pid" in ''|*[!0-9]*) exit 1;;esac
test "$(readlink /proc/"$pid"/exe)" = /data/home-ikev2/bin/charon
kill -KILL "$pid"
for i in $(seq 1 30); do
 next=$(cat /data/home-ikev2/control/daemon.pid)
 [ "$next" != "$pid" ] && break
 sleep 1
done
test "$next" != "$pid"
ready
printf 'crash-recovered\n' >"$base/status"
await finish
printf 'finished\n' >"$base/status"
