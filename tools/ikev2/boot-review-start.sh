#!/bin/sh
set -eu
umask 077
test "${1:-}" = authorized-controlled-reboot
base=/data/home-ikev2
full=$base/full-review
boot=$base/boot-review
test ! -f "$base/enabled"
test ! -f /data/home-tunnel/enabled
test ! -f "$base/routing-owned"
test ! -f "$base/xfrm-cleanup-pending"
test ! -f "$full/armed"
test ! -f "$boot/armed"
test ! -e /sys/class/net/x28ikev2
test "$("$base/bin/owned-xfrm" --check)" = 'owned_policies=0 owned_states=0'
test -r /proc/sys/kernel/random/boot_id
if netstat -lnut | grep -Eq ':(18444|15355)[[:space:]]';then exit 1;fi
rm -f "$full/cleanup-status" "$boot/status" "$boot/rollback-status" "$boot/watchdog-boot-id" "$boot/abort"
cat /proc/sys/kernel/random/boot_id >"$boot/before-boot-id"
touch "$full/armed" "$boot/armed"
sh "$full/watchdog.sh" >"$full/watchdog.log" 2>&1 &
watchdog=$!
printf '%s\n' "$watchdog" >"$full/watchdog.pid"
rollback() {
 code=$?
 trap - EXIT INT TERM HUP
 if [ "$code" != 0 ];then
  if sh "$full/cleanup.sh";then kill "$watchdog" 2>/dev/null || true;fi
  printf 'preboot-failed\n' >"$boot/status"
 fi
 exit "$code"
}
trap rollback EXIT
trap 'exit 1' INT TERM HUP
lua - <<'SELECT'
local fs=require 'nixio.fs'
local m=require 'luci.model.home_ikev2'
local s=m.summary()
local choice
for _,p in ipairs(s.profiles) do
 if p.server=='45.136.155.55' and p.identity=='tr-ist.prod.surfshark.com' then choice=p.index;break end
end
assert(choice,'Tested IP profile required')
assert(fs.writefile('/data/home-ikev2/full-review/previous-selection',tostring(s.selected)))
assert(m.select(choice))
SELECT
/etc/init.d/home-ikev2-boot-review enable
/usr/libexec/home-ikev2-control trial >"$boot/start.log" 2>&1
ready=0
for i in $(seq 1 60);do
 test ! -f "$boot/abort"
 if lua -e 'os.exit(require("luci.model.home_ikev2").summary().running and 0 or 1)';then ready=1;break;fi
 sleep 1
done
test "$ready" = 1
test ! -f "$boot/abort"
/etc/init.d/home-ikev2 enable
test -e /etc/rc.d/S17home-ikev2-boot-review
test -e /etc/rc.d/S18home-ikev2
printf 'reboot-dispatched\n' >"$boot/status"
lua - <<'REBOOT'
local n=require 'nixio'
local pid=assert(n.fork())
if pid==0 then
 assert(n.setsid())
 local c='sleep 2; test ! -f /data/home-ikev2/boot-review/abort || exit 1; exec /sbin/reboot'
 n.exec('/bin/sh','-c',c);os.exit(1)
end
REBOOT
trap - EXIT INT TERM HUP
echo CONTROLLED_REBOOT_DISPATCHED
