#!/bin/sh
set -eu
umask 077
base=/data/home-ikev2
test -x "$base/bin/charon"
test -x "$base/bin/swanctl"
test ! -e /sys/class/net/x28ikev2
if pidof charon >/dev/null; then echo EXISTING_IKE_DAEMON_TEST_REFUSED; exit 1; fi
ip xfrm state count | grep -q 'SAD count 0'
ip xfrm policy count | grep -q 'SPD IN  0 OUT 0 FWD 0'
mkdir -m700 "$base/check.lock"
mkdir -p /tmp/home-ikev2
chmod 700 /tmp/home-ikev2
pid=
watchdog=
cleanup() {
 code=$?
 trap - EXIT INT TERM HUP
 if [ -n "$pid" ] && [ "$(readlink /proc/$pid/exe 2>/dev/null)" = "$base/bin/charon" ]; then
  kill -TERM "$pid" 2>/dev/null || true
  sleep 2
  if [ "$(readlink /proc/$pid/exe 2>/dev/null)" = "$base/bin/charon" ]; then kill -KILL "$pid" 2>/dev/null || true; fi
  wait "$pid" 2>/dev/null || true
 fi
 if [ -n "$watchdog" ]; then kill "$watchdog" 2>/dev/null || true; fi
 rm -f "$base/check/swanctl.conf" "$base/check/ca.pem" "$base/check/charon.vici"
 rmdir "$base/check.lock"
 exit "$code"
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
lua - <<'LUA'
local fs=require 'nixio.fs'
local n=require 'nixio'
local m=require 'luci.model.home_ikev2'
local p=assert(m.selected_profile())
assert(fs.mkdirr('/data/home-ikev2/check'))
assert(fs.chmod('/data/home-ikev2/check','700'))
local function write(name,value)
 local f=assert(n.open('/data/home-ikev2/check/'..name,'w','600'))
 assert(f:writeall(value));f:close()
end
write('ca.pem',p.certificate)
write('swanctl.conf',assert(m.test_configuration(p)))
LUA
cat >"$base/check/strongswan.conf" <<'CONF'
charon {
 install_routes = no
 install_virtual_ip = no
 initiator_only = yes
 threads = 16
 load = des md4 openssl random nonce pem x509 pkcs1 pkcs8 pubkey constraints revocation kdf kernel-netlink socket-default vici eap-identity eap-mschapv2
 plugins {
  vici {
   socket = unix:///data/home-ikev2/check/charon.vici
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
export STRONGSWAN_CONF="$base/check/strongswan.conf"
"$base/bin/charon" >"$base/check/daemon.log" 2>&1 &
pid=$!
(sleep 60; if [ "$(readlink /proc/$pid/exe 2>/dev/null)" = "$base/bin/charon" ]; then kill -TERM "$pid" 2>/dev/null || true; fi) &
watchdog=$!
i=0
while [ ! -S "$base/check/charon.vici" ]; do
 kill -0 "$pid"
 i=$((i+1)); test "$i" -lt 10
 sleep 1
done
uri=unix:///data/home-ikev2/check/charon.vici
"$base/bin/swanctl" --stats --uri "$uri" >"$base/check/stats.log" 2>&1
grep -q eap-mschapv2 "$base/check/stats.log"
grep -q eap-identity "$base/check/stats.log"
grep -q x509 "$base/check/stats.log"
printf 'static-arm64-strongswan-6.1.0\n' >"$base/runtime-verified"
"$base/bin/swanctl" --load-all --file "$base/check/swanctl.conf" --uri "$uri" >"$base/check/load.log" 2>&1
if "$base/bin/swanctl" --initiate --child isolated --timeout 25 --uri "$uri" >"$base/check/auth.log" 2>&1; then
 echo IKEV2_AUTHENTICATED_WITH_ISOLATED_CHILD
else
 echo IKEV2_AUTH_CHECK_DID_NOT_CONNECT
fi
"$base/bin/swanctl" --list-sas --raw --uri "$uri" >"$base/check/sa.log" 2>&1
echo NO_LAN_ROUTE_OR_INTERFACE_WAS_CREATED
