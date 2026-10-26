FROM alpine:3.20
RUN apk add --no-cache postgresql16-client aws-cli gzip coreutils tzdata
COPY backup.sh restore.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/backup.sh /usr/local/bin/restore.sh \
    && echo '30 2 * * * /usr/local/bin/backup.sh >> /proc/1/fd/1 2>&1' > /etc/crontabs/root
# 02:30 IST nightly (TZ=Asia/Kolkata); crond in the foreground.
CMD ["crond", "-f", "-l", "8"]
