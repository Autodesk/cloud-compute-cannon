# Python Dockerfile
FROM ubuntu:14.04

# Install Python.
RUN \
  apt-get update && \
  apt-get install -y python && \
  rm -rf /var/lib/apt/lists/*

# Define working directory.
ENV app /app

RUN mkdir $app
COPY run.py $app/

WORKDIR $app

# Define default command.
CMD python run.py