#!/bin/sh
set -eu
gcc -std=c11 -Os -Wall -Wextra -Werror -static /source/tools/ikev2/owned-xfrm.c -o /out/owned-xfrm
gcc -std=c11 -Os -Wall -Wextra -Werror -Wno-unused-function -static /source/tests/owned-xfrm.c -o /out/test-owned-xfrm
/out/test-owned-xfrm
gcc -std=c11 -Os -Wall -Wextra -Werror -Wno-unused-function -static /source/tests/owned-xfrm-kernel.c -o /out/test-owned-xfrm-kernel
strip /out/owned-xfrm
if readelf -l /out/owned-xfrm | grep -q INTERP;then exit 1;fi
if readelf -d /out/owned-xfrm | grep -q NEEDED;then exit 1;fi
readelf -h /out/owned-xfrm | grep -q AArch64
sha256sum /out/owned-xfrm
