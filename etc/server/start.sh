#!/usr/bin/env sh
dc="/opt/bin/docker-compose"
$dc stop && $dc rm -f && $dc build && $dc up -d --remove-orphans