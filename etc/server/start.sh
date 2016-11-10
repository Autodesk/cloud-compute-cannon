#!/usr/bin/env sh
docker-compose stop && docker-compose rm -f && docker-compose build && docker-compose up -d --remove-orphans