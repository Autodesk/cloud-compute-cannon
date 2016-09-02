FROM fluent/fluentd:v0.14.2
MAINTAINER Dion Amago Whitehead <dion.amago@autodesk.com>
USER root
RUN apk --no-cache --update add \
    					build-base \
    					ruby-dev && \
    gem install fluent-plugin-elasticsearch && \
    apk del build-base ruby-dev && \
    rm -rf /tmp/* /var/tmp/* /var/cache/apk/*
USER fluent

EXPOSE 24225 9880
CMD fluentd -c /fluentd/etc/fluent.conf -p /fluentd/plugins $FLUENTD_OPT