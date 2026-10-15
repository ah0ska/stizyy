#!/bin/bash
# В xray/ должны лежать: xray, geoip.dat, geosite.dat, tun2socks (для VPN-режима)
set -e
cd "$(dirname "$0")"
APP=build/stizyy.app
rm -rf build && mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
swiftc -O -target x86_64-apple-macosx10.13 Sources/*.swift -o $APP/Contents/MacOS/stizyy
cp Info.plist $APP/Contents/
cp stizyy.icns $APP/Contents/Resources/
cp xray/* $APP/Contents/Resources/
cp tun.sh $APP/Contents/Resources/
chmod +x $APP/Contents/Resources/xray $APP/Contents/Resources/tun.sh
[ -f $APP/Contents/Resources/tun2socks ] && chmod +x $APP/Contents/Resources/tun2socks
xattr -cr $APP 2>/dev/null || true
codesign --force --deep --sign - $APP
echo "Готово: $APP"
