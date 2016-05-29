#!/usr/bin/env sh

rm -rf build/publish
mkdir -p build/publish/bin

haxe etc/hxml/cli-build.hxml

cp build/cli/cloudcomputecannon.js build/publish/bin/
cp build/cli/cloudcomputecannon.js.map build/publish/bin/
cp package.json build/publish/package.json
cp README.md build/publish/README.md

cd build/publish
npm publish .

