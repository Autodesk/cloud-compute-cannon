FROM alpine:3.4
MAINTAINER Dion Amago Whitehead

RUN apk add --no-cache nodejs && \
	rm -rf /tmp/* /var/tmp/* /var/cache/apk/*

ENV NODE_PATH /usr/lib/node_modules/
RUN npm install --global dockerode

ENV APP /app
RUN mkdir -p $APP
WORKDIR $APP

ADD script.js $APP/script.js

CMD ["node", "/app/script.js"]