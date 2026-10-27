#!/bin/sh
set -eu
umask 077
base=/data/home-ikev2
job=$base/crash-check
test ! -f "$base/enabled"
test ! -f "$base/routing-owned"
test ! -e /sys/class/net/x28ikev2
if pidof charon >/dev/null;then exit 1;fi
ip xfrm state count | grep -q 'SAD count 0'
ip xfrm policy count | grep -q 'SPD IN  0 OUT 0 FWD 0'
mkdir -m700 "$base/check.lock"
mkdir -p /tmp/home-ikev2
chmod 700 /tmp/home-ikev2
rm -f "$job/cleanup-status" "$job/exit-code"
touch "$job/armed"
sh "$job/watchdog.sh" >"$job/watchdog.log" 2>&1 &
watchdog=$!
pid=
cleanup() {
 code=$?
 trap - EXIT INT TERM HUP
 if sh "$job/cleanup.sh";then kill "$watchdog" 2>/dev/null || true;else code=1;fi
 if [ -n "$pid" ];then wait "$pid" 2>/dev/null || true;fi
 printf '%s\n' "$code" >"$job/exit-code"
 exit "$code"
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
lua - <<'CONFIG'
local fs=require 'nixio.fs'
local n=require 'nixio'
local j=require 'luci.jsonc'
local m=require 'luci.model.home_ikev2'
local s=assert(j.parse(fs.readfile('/data/home-ikev2/profiles.json')))
local profile
for _,p in ipairs(s.profiles) do
 if p.server=='45.136.155.55' and p.identity=='tr-ist.prod.surfshark.com' then profile=p;break end
end
assert(profile,'Verified IP profile required')
local function write(name,value)
 local f=assert(n.open('/data/home-ikev2/crash-check/'..name,'w','600'));assert(f:writeall(value));f:close()
end
write('ca.pem',profile.certificate)
local config=assert(m.test_configuration(profile))
config=config:gsub('/check/ca.pem','/crash-check/ca.pem',1)
config=config:gsub(' start_action = none',' reqid = 20290\n start_action = none',1)
write('swanctl.conf',config)
CONFIG
cat >"$base/crash-check/strongswan.conf" <<'CONF'
charon {
 install_routes = no
 install_virtual_ip = no
 initiator_only = yes
 threads = 16
 load = des md4 openssl random nonce pem x509 pkcs1 pkcs8 pubkey constraints revocation kdf kernel-netlink socket-default vici eap-identity eap-mschapv2
 plugins {
  vici {
   socket = unix:///data/home-ikev2/crash-check/charon.vici
  }
  kernel-netlink {
   install_routes_xfrmi = no
  }
 }
 filelog {
  stderr {
   default = 0
   flush_line = yes
  }
 }
}
swanctl {
 load = des md4 openssl random nonce pem x509 pkcs1 pkcs8 pubkey constraints revocation kdf
}
CONF
export STRONGSWAN_CONF="$job/strongswan.conf"
uri=unix:///data/home-ikev2/crash-check/charon.vici
for round in 1 2;do
 rm -f "$job/charon.vici"
 "$base/bin/charon" >"$job/daemon-$round.log" 2>&1 &
 pid=$!
 printf '%s\n' "$pid" >"$job/daemon.pid"
 for i in 1 2 3 4 5 6 7 8 9 10;do
  test -f "$job/armed";kill -0 "$pid"
  test -S "$job/charon.vici" && break
  sleep 1
 done
 test -S "$job/charon.vici"
 timeout 20 "$base/bin/swanctl" --load-all --file "$job/swanctl.conf" --uri "$uri" >"$job/load-$round.log" 2>&1
 timeout 20 "$base/bin/swanctl" --initiate --child isolated --timeout 15 --uri "$uri" >"$job/auth-$round.log" 2>&1
 test "$("$base/bin/owned-xfrm" --check)" = 'owned_policies=3 owned_states=2'
 echo AUTHENTICATED_ROUND_$round
 if [ "$round" = 1 ];then
  kill -KILL "$pid"
  wait "$pid" 2>/dev/null || true
  test "$("$base/bin/owned-xfrm" --check)" = 'owned_policies=3 owned_states=2'
  "$base/bin/owned-xfrm" --delete-owned
  test "$("$base/bin/owned-xfrm" --check)" = 'owned_policies=0 owned_states=0'
  echo FORCED_CRASH_KERNEL_CLEANUP_PASSED
 fi
done
echo ROUTER_ONLY_CRASH_AND_REAUTHENTICATION_PASSED
