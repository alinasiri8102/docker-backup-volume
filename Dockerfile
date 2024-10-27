FROM alpine:latest

WORKDIR /app

COPY backup-script.sh /backup-script.sh

RUN apk add --no-cache docker-cli bash curl tar gzip \
    && chmod +x /backup-script.sh

ENTRYPOINT ["/bin/sh", "/backup-script.sh"]
