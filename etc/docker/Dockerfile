FROM node:8.6.0-alpine
MAINTAINER Dion Amago Whitehead

ENV APP /app
RUN mkdir -p $APP
WORKDIR $APP

RUN npm install -g forever && touch $APP/.foreverignore

ADD package.json $APP/package.json

RUN apk add --no-cache make gcc g++ python linux-headers udev git && \
	npm install --quiet && \
	apk del make gcc g++ python linux-headers udev git && \
	rm -rf /tmp/* /var/tmp/* /var/cache/apk/*

ENV PORT 9000
EXPOSE 9000

ADD server $APP/server
ADD web $APP/web
ADD etc $APP/etc
COPY VERSION $APP/VERSION

CMD forever server/cloud-compute-cannon-server.js