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
	apk del make gcc g++ python linux-headers udev

COPY ::APP_SERVER_FILE:: $APP/
COPY ::APP_SERVER_FILE::.map $APP/

ENV PORT 9000
EXPOSE $PORT

CMD node ::APP_SERVER_FILE::