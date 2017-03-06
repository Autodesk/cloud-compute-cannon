#!/usr/bin/env sh

VERSION=`cat /src/package.json | jq -r '. .version'`
LAMBDA_NAME=`cat /src/package.json | jq -r '. .name'`
HANDLER=`cat /src/package.json | jq -r '. .handler'`
FILENAME=lambda-$LAMBDA_NAME-$VERSION.zip

echo "FILENAME=$FILENAME"
echo "HANDLER=$HANDLER"

# Reference: http://docs.aws.amazon.com/cli/latest/reference/lambda/create-function.html
aws lambda create-function \
    --region us-west-1 \
    --function-name $LAMBDA_NAME-07 \
    --environment Variables={CCC_URL=http://54.193.56.129:9001/api/rpc/status} \
    --zip-file fileb:///dist/$FILENAME \
    --role arn:aws:iam::763896067184:role/lambda_basic_execution_ro \
    --handler $HANDLER \
    --runtime nodejs4.3 \
    --timeout 10
