FROM alpine:3.20

RUN apk add --no-cache \
    postgresql16-client \
    aws-cli \
    gzip \
    tzdata \
    dcron

COPY backup.sh /usr/local/bin/backup.sh
RUN chmod +x /usr/local/bin/backup.sh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
