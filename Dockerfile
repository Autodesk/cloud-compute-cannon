FROM ubuntu:14.04
MAINTAINER Dion Whitehead Amago

# Haxe environment variables
ENV HAXE_STD_PATH /root/haxe/std/
ENV PATH /root/haxe/:$PATH
# Neko environment variables
ENV NEKOPATH /root/neko/
ENV LD_LIBRARY_PATH /root/neko/
ENV PATH /root/neko/:$PATH

ENV HAXE_DOWNLOAD_URL http://haxe.org/website-content/downloads/3.3.0-rc.1/downloads/haxe-3.3.0-rc.1-linux64.tar.gz

# Dependencies
RUN apt-get update && \
	apt-get install -y wget curl g++ g++-multilib libgc-dev git python build-essential && \
	curl -sL https://deb.nodesource.com/setup_4.x | sudo -E bash - && \
	sudo apt-get -y install nodejs && \
	apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* && \
	mkdir /root/haxe && \
	wget -O - $HAXE_DOWNLOAD_URL | tar xzf - --strip=1 -C "/root/haxe" && \
	mkdir /root/neko && \
	wget -O - http://nekovm.org/_media/neko-2.0.0-linux64.tar.gz | tar xzf - --strip=1 -C "/root/neko"

ENV APP /app
RUN mkdir -p $APP
WORKDIR $APP

RUN haxelib newrepo

#Only install npm packages if the package.json changes
ADD ./package.json $APP/package.json
RUN npm install
RUN npm install -g forever nodemon bunyan

#Only install haxe packages if the package.json changes
ADD ./etc/hxml/base.hxml $APP/etc/hxml/base.hxml
ADD ./etc/hxml/base-nodejs.hxml $APP/etc/hxml/base-nodejs.hxml
RUN npm run install-dependencies

COPY ./ $APP/

RUN	haxe etc/hxml/build-all.hxml

ENV PORT 9000
EXPOSE $PORT
EXPOSE 9001
EXPOSE 9002

WORKDIR $APP/build

#Do not watch the entire tree, just that file. Limit retries to 5
CMD forever -m 5 --watchDirectory server server/cloud-compute-cannon-server.js


