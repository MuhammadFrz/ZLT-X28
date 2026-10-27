#!/bin/sh
set -eu
source=$1
work=$(mktemp -d)
trap 'rm -f "$work/function" "$work/calls"; rmdir "$work"' EXIT
sed -n '/^ensure4() {/,/^}/p' "$source" >"$work/function"
. "$work/function"
four() {
 printf '%s\n' "$*" >>"$work/calls"
 case " $* " in *' -C '*) return 1;;esac
}
ensure4 -t nat POSTROUTING -o tun0 -j X28_OVPN_S
ensure4 FORWARD -i br0 -j X28_OVPN_F
test "$(sed -n '1p' "$work/calls")" = '-t nat -C POSTROUTING -o tun0 -j X28_OVPN_S'
test "$(sed -n '2p' "$work/calls")" = '-t nat -I POSTROUTING -o tun0 -j X28_OVPN_S'
test "$(sed -n '3p' "$work/calls")" = '-C FORWARD -i br0 -j X28_OVPN_F'
test "$(sed -n '4p' "$work/calls")" = '-I FORWARD -i br0 -j X28_OVPN_F'
echo 'OpenVPN filter and NAT insertion regression passed'
