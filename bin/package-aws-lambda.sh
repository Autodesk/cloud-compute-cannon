#!/usr/bin/env bash

if [ $# -eq 0 ]; then
	echo ""
    echo "    Package an AWS Lambda script with all node modules into a zip file"
    echo "    The packager runs in an AWS Linux docker container, so the node "
    echo "    modules are compiled for the correct architecture."
    echo ""
    echo "    -s/--src            The source folder of the lambda script"
    echo "    -d/--destination    The destination folder for the lambda zip file"
    echo ""
    exit 0
fi

# Use -gt 1 to consume two arguments per pass in the loop (e.g. each
# argument has a corresponding value to go with it).
# Use -gt 0 to consume one or more arguments per pass in the loop (e.g.
# some arguments don't have a corresponding value to go with it such
# as in the --default example).
# note: if this is set to -gt 0 the /etc/hosts part is not recognized ( may be a bug )
while [[ $# -gt 1 ]]
do
key="$1"

case $key in
    -s|--src)
    SRC="$2"
    shift # past argument
    ;;
    -d|--destination)
    DESTINATION="$2"
    shift # past argument
    ;;
    *)
            # unknown option
    ;;
esac
shift # past argument or value
done

while [[ $# -gt 0 ]]
do
key="$1"

case $key in
    -c|--container)
    CONTAINER=YES
    ;;
    *)
            # unknown option
    ;;
esac
shift # past argument or value
done

DOCKER_IMAGE="create-lambda-amazon-linux"
DOCKER_FILE_DIR="/tmp/$DOCKER_IMAGE"

set -e

if [ "$CONTAINER" = "YES" ]; then
	if [ ! -f package.json ]; then
		echo "Cannot create lambda package, 'package.json' file not found!"
		exit 1
	fi
	VERSION=`cat package.json | jq -r '. .version'`
	LAMBDA_NAME=`cat package.json | jq -r '. .name'`
	FILENAME=lambda-$LAMBDA_NAME-$VERSION.zip
	npm install || exit 1
	zip -r /destination/$FILENAME . || exit 1
else
	mkdir -p $DOCKER_FILE_DIR
	#Create the Dockerfile, and build the image
	cat > $DOCKER_FILE_DIR/Dockerfile << EOF
FROM amazonlinux:2017.09

RUN mkdir /tmp/docker-build && \\
  yum -y update && \\
  curl -X GET -o /tmp/docker-build/RPM-GPG-KEY-lambda-epll \\
  https://lambda-linux.io/RPM-GPG-KEY-lambda-epll && \\
  rpm --import /tmp/docker-build/RPM-GPG-KEY-lambda-epll && \\
  curl -X GET -o /tmp/docker-build/epll-release-2016.09-1.2.ll1.noarch.rpm \\
    https://lambda-linux.io/epll-release-2016.09-1.2.ll1.noarch.rpm && \\
  yum install -y /tmp/docker-build/epll-release-2016.09-1.2.ll1.noarch.rpm && \\
  yum --enablerepo=epll-preview install -y nodejs6 && \\
  yum install -y gcc gcc-c++ make && \\
  yum install -y aws-cli && \\
  yum install -y zip && \\
  yum install -y jq && \\
  yum clean all && \\
  rm -rf /var/cache/yum/* && \\
  rm -rf /tmp/* && \\
  rm -rf /var/tmp/*
EOF
	if [[ "$(docker images -q $DOCKER_IMAGE 2> /dev/null)" == "" ]]; then
		docker build -t $DOCKER_IMAGE -f $DOCKER_FILE_DIR/Dockerfile $DOCKER_FILE_DIR
	fi

	#Now execute this script again, but inside the container!
	if [[ $SRC == /* ]]; then
		true
	else
		SRC=`pwd`/$SRC
	fi

	if [[ $DESTINATION == /* ]]; then
		true
	else
		DESTINATION=`pwd`/$DESTINATION
	fi
	ME=`basename "$0"`
	DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
	docker run --rm -ti -v $SRC:/src -v $DESTINATION:/destination -v $DIR/$ME:/$ME -w /src $DOCKER_IMAGE /$ME -s /src -d /destination --container
fi