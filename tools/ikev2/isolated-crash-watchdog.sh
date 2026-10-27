#!/bin/sh
set -eu
sleep 120 &
timer=$!
trap 'kill "$timer" 2>/dev/null || true;exit 0' INT TERM
wait "$timer"
exec sh /data/home-ikev2/crash-check/cleanup.sh
