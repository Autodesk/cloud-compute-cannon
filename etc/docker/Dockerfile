FROM alpine:3.4
MAINTAINER Dion Whitehead Amago

ENV APP /app
RUN mkdir -p $APP
WORKDIR $APP

ADD package.json $APP/package.json

RUN apk add --no-cache nodejs && \
	apk add --no-cache make gcc g++ python linux-headers udev && \
	npm install && \
	npm install -g forever nodemon && \
	apk del make gcc g++ python linux-headers udev && \
	rm -rf /tmp/* /var/tmp/* /var/cache/apk/* && \
	touch $APP/.foreverignore

ENV PORT 9000
EXPOSE $PORT

ADD server $APP/server
ADD web $APP/web
COPY VERSION $APP/VERSION

CMD forever server/cloud-compute-cannon-server.js