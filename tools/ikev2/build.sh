#!/bin/sh
set -eu
apk add --no-cache build-base linux-headers openssl-dev openssl-libs-static curl gnupg bzip2 python3
mkdir -p /build /out
cd /build
curl --fail --location --proto '=https' --tlsv1.2 -o source.tar.bz2 https://download.strongswan.org/strongswan-6.1.0.tar.bz2
curl --fail --location --proto '=https' --tlsv1.2 -o source.sig https://download.strongswan.org/strongswan-6.1.0.tar.bz2.sig
curl --fail --location --proto '=https' --tlsv1.2 -o key.asc https://download.strongswan.org/STRONGSWAN-RELEASE-PGP-KEY
gpg --import key.asc
gpg --status-fd 1 --verify source.sig source.tar.bz2 > /out/signature.txt 2>&1
grep -q 'GOODSIG DF42C170B34DBA77' /out/signature.txt
sha256sum source.tar.bz2 > /out/source.sha256
tar -xjf source.tar.bz2
cd strongswan-6.1.0
./configure --prefix=/data/home-ikev2/runtime --sysconfdir=/data/home-ikev2/etc \
 --with-piddir=/tmp/home-ikev2 --disable-defaults --disable-shared --enable-static \
 --enable-monolithic --enable-charon --enable-ikev2 --enable-swanctl --enable-vici \
 --enable-kernel-netlink --enable-socket-default --enable-openssl --enable-random \
 --enable-nonce --enable-pem --enable-x509 --enable-pkcs1 --enable-pkcs8 \
 --enable-pubkey --enable-constraints --enable-revocation --enable-kdf \
 --enable-eap-identity --enable-eap-mschapv2 --enable-md4 --enable-des \
 CFLAGS='-Os' LDFLAGS='-static' > /out/configure.log 2>&1
make -j2 LDFLAGS=-all-static > /out/make.log 2>&1
make install DESTDIR=/stage > /out/install.log 2>&1
make -C src/xfrmi LDFLAGS=-all-static > /out/relink-xfrmi.log 2>&1
mkdir -p /out/bin
cp /stage/data/home-ikev2/runtime/libexec/ipsec/charon /out/bin/
cp /stage/data/home-ikev2/runtime/sbin/swanctl /out/bin/
cp src/xfrmi/xfrmi /out/bin/xfrmi
strip /out/bin/charon /out/bin/swanctl /out/bin/xfrmi
readelf -h /out/bin/charon > /out/elf.txt
if readelf -l /out/bin/charon | grep -q INTERP; then echo 'Dynamic charon rejected'; exit 1; fi
if readelf -l /out/bin/swanctl | grep -q INTERP; then echo 'Dynamic swanctl rejected'; exit 1; fi
if readelf -l /out/bin/xfrmi | grep -q INTERP; then echo 'Dynamic xfrmi rejected'; exit 1; fi
printf 'swanctl {\n}\n' > /out/smoke.conf
STRONGSWAN_CONF=/out/smoke.conf /out/bin/swanctl --help > /out/version.txt 2>&1
sha256sum /out/bin/* > /out/binaries.sha256
cp COPYING /out/LICENSE.strongswan
echo ISOLATED_ARM64_BUILD_PASSED
