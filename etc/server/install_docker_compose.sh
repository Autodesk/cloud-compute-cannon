#!/bin/bash
mkdir -p /opt/bin
curl -L `curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.assets[].browser_download_url | select(contains("Linux") and contains("x86_64"))'` > /opt/bin/docker-compose
chmod +x /opt/bin/docker-compose


# curl -L `curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.assets[].browser_download_url | select(contains("Linux") and contains("x86_64"))'` > /tmp/docker-compose
# sudo mv /tmp/docker-compose /opt/bin/docker-compose
# sudo chmod +x /opt/bin/docker-compose