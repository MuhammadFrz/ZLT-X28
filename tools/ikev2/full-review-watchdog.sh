#!/bin/sh
set -eu
sleep 300 &
timer=$!
trap 'kill "$timer" 2>/dev/null || true;exit 0' INT TERM
wait "$timer"
exec sh /data/home-ikev2/full-review/cleanup.sh
