FROM amazonlinux:2016.09

RUN \
  # Create temporary build directory
  mkdir /tmp/docker-build && \
  \
  # Update RPM packages
  yum -y update && \
  \
  # Setup epll-preview repository
  curl -X GET -o /tmp/docker-build/RPM-GPG-KEY-lambda-epll \
  https://lambda-linux.io/RPM-GPG-KEY-lambda-epll && \
  rpm --import /tmp/docker-build/RPM-GPG-KEY-lambda-epll && \
  curl -X GET -o /tmp/docker-build/epll-release-2016.09-1.2.ll1.noarch.rpm \
    https://lambda-linux.io/epll-release-2016.09-1.2.ll1.noarch.rpm && \
  yum install -y /tmp/docker-build/epll-release-2016.09-1.2.ll1.noarch.rpm && \
  \
  # Install nodejs6
  yum --enablerepo=epll-preview install -y nodejs6 && \
  yum install -y gcc gcc-c++ make && \
  # Install aws cli
  yum install -y aws-cli && \
  yum install -y zip && \
  yum install -y jq && \
  \
  # Clean up
  yum clean all && \
  rm -rf /var/cache/yum/* && \
  rm -rf /tmp/* && \
  rm -rf /var/tmp/*
