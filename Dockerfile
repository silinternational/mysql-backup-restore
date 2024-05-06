FROM python:3-alpine

# Variables set with ARG can be overridden at image build time with
# "--build-arg var=value".  They are not available in the running container.
ARG B2_VERSION=v3.19.1

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
 && wget -O /usr/local/bin/b2 \
    https://github.com/Backblaze/B2_Command_Line_Tool/releases/download/${B2_VERSION}/b2-linux \
 && chmod +x /usr/local/bin/b2

COPY application/ /data/
WORKDIR /data

CMD ["./entrypoint.sh"]
