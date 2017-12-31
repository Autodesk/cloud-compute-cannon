#!/bin/bash
docker run --restart=always -p 6379:6379 --detach redis:3.2.0-alpine
