#!/bin/sh
set -eu
base=/data/home-ikev2
job=$base/crash-check
test -f "$job/armed" || exit 0
if [ -f "$job/daemon.pid" ];then
 p=$(cat "$job/daemon.pid")
 case "$p" in ''|*[!0-9]*) exit 1;;esac
 if [ "$(readlink /proc/"$p"/exe 2>/dev/null)" = "$base/bin/charon" ];then
  kill -TERM "$p" 2>/dev/null || true;sleep 2
  if [ "$(readlink /proc/"$p"/exe 2>/dev/null)" = "$base/bin/charon" ];then kill -KILL "$p";fi
 fi
fi
if ! "$base/bin/owned-xfrm" --delete-owned;then touch "$base/xfrm-cleanup-pending";exit 1;fi
test ! -e /sys/class/net/x28ikev2
ip xfrm state count | grep -q 'SAD count 0'
ip xfrm policy count | grep -q 'SPD IN  0 OUT 0 FWD 0'
rm -f "$job/armed" "$job/swanctl.conf" "$job/ca.pem" "$job/charon.vici"
rmdir "$base/check.lock" 2>/dev/null || test ! -d "$base/check.lock"
printf 'completed\n' >"$job/cleanup-status"
