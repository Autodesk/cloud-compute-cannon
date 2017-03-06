#!/usr/bin/env sh
docker-compose -f deploy/docker-compose.yml build
if [ -z "$1" ]
	then
	echo 'Requires src path as the first argument'
    exit 1
fi
SRC=`realpath $1`
if [ -z "$2" ]
  then
    DESTINATION=`pwd`/build/$1
  else
	DESTINATION=`realpath $2`
fi
echo "SRC=$SRC"
echo "DESTINATION=$DESTINATION"
SRC=$SRC DESTINATION=$DESTINATION docker-compose -f deploy/docker-compose.yml up