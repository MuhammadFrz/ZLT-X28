#!/bin/sh
set -eu
umask 077
base=/data/home-ikev2/boot-review
full=/data/home-ikev2/full-review
test -f "$base/armed" || exit 0
test -f "$full/armed" || exit 0
exec >"$base/watchdog.log" 2>&1
if ! current=$(cat /proc/sys/kernel/random/boot_id) || ! previous=$(cat "$base/before-boot-id");then
 sh "$full/cleanup.sh"
 exit 1
fi
test "$current" != "$previous" || exit 0
timer=
cleanup() {
 trap - EXIT INT TERM HUP
 if [ -n "$timer" ]; then kill "$timer" 2>/dev/null || true;wait "$timer" 2>/dev/null || true;fi
 if [ -f "$full/armed" ]; then
  if sh "$full/cleanup.sh" >"$base/rollback.log" 2>&1;then
   rm -f "$base/armed";printf 'restored\n' >"$base/rollback-status"
  else
   printf 'failed\n' >"$base/rollback-status";exit 1
  fi
 else
  rm -f "$base/armed";printf 'cancelled\n' >"$base/rollback-status"
 fi
}
trap cleanup EXIT
trap 'exit 1' INT TERM HUP
sleep 300 &
timer=$!
printf '%s\n' "$current" >"$base/watchdog-boot-id"
# Only the computer's test ports are added; production routing is untouched here.
touch "$full/fixture-owned"
iptables -w 3 -t nat -N X28_IKE_REVIEW 2>/dev/null || iptables -w 3 -t nat -S X28_IKE_REVIEW >/dev/null
iptables -w 3 -t nat -C X28_IKE_REVIEW -p tcp --dport 18444 -j DNAT --to-destination 1.1.1.1:443 2>/dev/null ||
 iptables -w 3 -t nat -A X28_IKE_REVIEW -p tcp --dport 18444 -j DNAT --to-destination 1.1.1.1:443
iptables -w 3 -t nat -C PREROUTING -i br0 -s 192.168.70.107 -d 192.168.70.1 -p tcp --dport 18444 -j X28_IKE_REVIEW 2>/dev/null ||
 iptables -w 3 -t nat -I PREROUTING 1 -i br0 -s 192.168.70.107 -d 192.168.70.1 -p tcp --dport 18444 -j X28_IKE_REVIEW
for protocol in udp tcp;do
 iptables -w 3 -t nat -C X28_IKE_REVIEW -p "$protocol" --dport 15355 -j DNAT --to-destination 8.8.8.8:53 2>/dev/null ||
  iptables -w 3 -t nat -A X28_IKE_REVIEW -p "$protocol" --dport 15355 -j DNAT --to-destination 8.8.8.8:53
 iptables -w 3 -t nat -C PREROUTING -i br0 -s 192.168.70.107 -d 192.168.70.1 -p "$protocol" --dport 15355 -j X28_IKE_REVIEW 2>/dev/null ||
  iptables -w 3 -t nat -I PREROUTING 1 -i br0 -s 192.168.70.107 -d 192.168.70.1 -p "$protocol" --dport 15355 -j X28_IKE_REVIEW
done
printf 'fixtures-ready\n' >"$base/status"
wait "$timer"
printf 'deadline-reached\n' >"$base/status"
