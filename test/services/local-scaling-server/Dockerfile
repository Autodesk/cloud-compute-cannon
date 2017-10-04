FROM dionjwa/haxe-watch:v0.5.3
MAINTAINER dion@transition9.com

WORKDIR /app
ADD package.json /app/package.json
RUN npm i
ADD build.hxml /app/build.hxml
RUN haxelib install --always build.hxml
ADD src /app/src
RUN haxe build.hxml

ENV PORT=4015
EXPOSE 4015
CMD nodemon build/cloud-compute-cannon-scaling-server.js
