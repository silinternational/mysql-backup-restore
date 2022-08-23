FROM python:3-alpine

RUN apk update \
 && apk add --no-cache \
            bash \
            mysql-client \
 && python -m pip install --upgrade pip \
 && pip install s3cmd python-magic

COPY application/ /data/
WORKDIR /data

CMD ["./entrypoint.sh"]
