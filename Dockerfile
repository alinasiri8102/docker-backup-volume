FROM alpine:latest

WORKDIR /app

COPY backup-script.sh /backup-script.sh

RUN apk add --no-cache docker-cli bash curl coreutils zip findutils && chmod +x /backup-script.sh
