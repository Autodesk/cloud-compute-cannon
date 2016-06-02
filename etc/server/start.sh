#!/usr/bin/env sh
docker-compose rm -fv && docker-compose build && docker-compose up -d --remove-orphans