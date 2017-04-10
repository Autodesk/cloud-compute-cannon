FROM redis:3.2.0-alpine
MAINTAINER Dion Whitehead Amago

EXPOSE 6379
ADD ./redis-prod.conf /usr/local/etc/redis/redis.conf
CMD redis-server /usr/local/etc/redis/redis.conf
