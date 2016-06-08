FROM python:2.7.11-alpine

# Define working directory.
ENV app /app

RUN mkdir $app
COPY run.py $app/

WORKDIR $app

# Define default command.
CMD python run.py