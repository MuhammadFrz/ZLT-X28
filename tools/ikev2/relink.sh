#!/bin/sh
set -eu
cd /build/strongswan-6.1.0
rm -f src/charon/charon src/swanctl/swanctl
make -C src/charon LDFLAGS=-all-static > /out/relink-charon.log 2>&1
make -C src/swanctl LDFLAGS=-all-static > /out/relink-swanctl.log 2>&1
make -C src/xfrmi LDFLAGS=-all-static > /out/relink-xfrmi.log 2>&1
cp src/xfrmi/xfrmi /out/bin/xfrmi
cp src/charon/charon /out/bin/charon
cp src/swanctl/swanctl /out/bin/swanctl
strip /out/bin/charon /out/bin/swanctl /out/bin/xfrmi
for name in charon swanctl xfrmi; do
 if readelf -l /out/bin/$name | grep -q INTERP; then echo 'Dynamic binary rejected'; exit 1; fi
 if readelf -d /out/bin/$name | grep -q NEEDED; then echo 'Shared dependency rejected'; exit 1; fi
done
printf 'swanctl {\n}\n' > /out/smoke.conf
STRONGSWAN_CONF=/out/smoke.conf /out/bin/swanctl --help > /out/version.txt 2>&1
sha256sum /out/bin/* > /out/binaries.sha256
cp COPYING /out/LICENSE.strongswan
readelf -h /out/bin/charon > /out/elf.txt
echo ISOLATED_STATIC_ARM64_BUILD_PASSED
