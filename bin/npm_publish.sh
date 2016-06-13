#!/usr/bin/env sh

git diff-index --quiet HEAD --
if [ $? -ne 0 ]
then
  echo "Uncommitted git changes"
  exit 1
fi

rm -rf build/publish
mkdir -p build/publish/bin

haxe etc/hxml/cli-build.hxml

cp build/cli/cloudcomputecannon.js build/publish/bin/
cp build/cli/cloudcomputecannon.js.map build/publish/bin/
cp package.json build/publish/package.json
cp README.md build/publish/README.md

cd build/publish
npm publish .

PACKAGE_VERSION=$(cat package.json \
  | grep version \
  | head -1 \
  | awk -F: '{ print $2 }' \
  | sed 's/[",]//g' \
  | tr -d '[[:space:]]')

git tag $PACKAGE_VERSION && git push --tags

