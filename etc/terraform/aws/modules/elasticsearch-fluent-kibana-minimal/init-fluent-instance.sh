#!/bin/bash

sudo curl -L https://github.com/docker/compose/releases/download/1.9.0/docker-compose-`uname -s`-`uname -m` | sudo tee /usr/local/bin/docker-compose > /dev/null
sudo chmod +x /usr/local/bin/docker-compose

#Create a docker-compose file for the fluent
cat << EOF > /tmp/docker-compose.yml
version: '2'
services:
  fluentd:
    restart: "always"
    image: openfirmware/fluentd-elasticsearch
    ports:
      - "8888:8888"
      - "24224:24224"
    links:
      - elasticsearch
    environment:
      - ES_HOST=elasticsearch
      - ES_PORT=9200
  elasticsearch:
    restart: "always"
    image: elasticsearch:2.4.5-alpine
    ports:
      - "9200:9200"
      - "9300:9300"
  kibana:
    restart: "always"
    image: kibana:4.6.6
    ports:
      - "5601:5601"
    environment:
      ELASTICSEARCH_URL: "http://elasticsearch:9200"
    links:
      - elasticsearch
EOF

#Run the docker-compose file
/usr/local/bin/docker-compose -f /tmp/docker-compose.yml up -d