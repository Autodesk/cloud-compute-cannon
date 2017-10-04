FROM dionjwa/haxe-watch:v0.7.3
MAINTAINER Dion Amago Whitehead

CMD ["/bin/bash"]

ENV APP /app
RUN mkdir -p $APP
WORKDIR $APP

RUN haxelib newrepo

#Only install haxe packages if the package.json changes
ADD ./clients/shared/hxml $APP/clients/shared/hxml
ADD ./etc/hxml $APP/etc/hxml
ADD ./etc/bionano/aws/cloudformation/lambda-autoscaling/src/build.hxml $APP/etc/bionano/aws/cloudformation/lambda-autoscaling/src/build.hxml
ADD ./test/services/stand-alone-tester/build.hxml $APP/test/services/stand-alone-tester/build.hxml
ADD ./test/services/local-scaling-server/build.hxml $APP/test/services/local-scaling-server/build.hxml

RUN haxelib install --always etc/hxml/build-all.hxml
