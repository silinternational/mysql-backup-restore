FROM python:3-alpine

# Current version of s3cmd is in edge/testing repo
RUN echo https://dl-cdn.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories

# Install everything via repo, because repo & pip installs can break things
RUN apk update \
    && apk add --no-cache \
            bash \
            mysql-client \
            py3-magic \
            py3-dateutil \
            py3-six \
            s3cmd \
            curl \
            jq
            
# Install sentry-cli
RUN curl -sL https://sentry.io/get-cli/ | bash

COPY application/ /data/
WORKDIR /data

CMD ["./entrypoint.sh"]
