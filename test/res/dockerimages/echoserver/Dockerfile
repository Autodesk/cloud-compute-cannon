FROM ubuntu:14.04
MAINTAINER Dion Whitehead Amago

# Dependencies
RUN apt-get update && \
	apt-get install -y wget curl g++ g++-multilib libgc-dev git python build-essential && \
	curl -sL https://deb.nodesource.com/setup_4.x | sudo -E bash - && \
	sudo apt-get -y install nodejs && \
	apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN npm install -g echo-server

ENV PORT 9000
EXPOSE $PORT

CMD echo-server $PORT


