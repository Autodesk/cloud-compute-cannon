#!/usr/bin/env sh

for hostName in serverstable serverbeta serveralpha; do
  rsync -av --delete --exclude=.git --exclude=build --exclude=.DS_Store --exclude=.empty --exclude=node_modules --exclude=.haxelib  --exclude=tmp  ./ $hostName:ccc/
done

