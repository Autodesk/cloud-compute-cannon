FROM fluent/fluentd:v0.12.21
MAINTAINER Dion Amago Whitehead <dion.amago@autodesk.com>
USER fluent
WORKDIR /home/fluent
ENV PATH /home/fluent/.gem/ruby/2.2.0/bin:$PATH
RUN gem install fluent-plugin-elasticsearch
RUN gem install fluent-plugin-parser

# COPY fluent.conf /fluentd/etc/
COPY plugins /fluentd/plugins

EXPOSE 24225 9880
CMD fluentd -c /fluentd/etc/$FLUENTD_CONF -p /fluentd/plugins $FLUENTD_OPT