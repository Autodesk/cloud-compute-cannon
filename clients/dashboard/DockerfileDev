FROM haxe:3.3.0-rc.1
MAINTAINER Dion Amago Whitehead

RUN curl -sL https://deb.nodesource.com/setup_6.x -o nodesource_setup.sh \
  && bash nodesource_setup.sh \
  && apt-get update && apt-get install -y \
  nodejs \
  build-essential \
  && apt-get clean && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

RUN npm install -g chokidar-cli nodemon

ENV APP /app
RUN mkdir -p $APP
WORKDIR $APP

RUN haxelib newrepo

#Only install haxe packages if the package.json changes
ADD ./build.hxml $APP/build.hxml
RUN haxelib install --always build.hxml

#NPM
ADD ./package.json $APP/package.json
RUN npm install

ADD ./web $APP/
ADD ./src $APP/
ADD ./test $APP/

RUN haxe build.hxml

CMD ["/bin/bash"]

