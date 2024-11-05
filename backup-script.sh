#!/bin/sh

BACKUP_DIR="/backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +"%Y-%m-%d_%H-%M-%S")
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-14}


send_telegram() {
    local archive_file=$1
    
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        response=$(curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F chat_id="${TELEGRAM_CHAT_ID}" \
            -F message_thread_id="${TELEGRAM_THREAD_ID}" \
            -F document="@$archive_file" \
            -F caption="📌 $DATE")
        if echo "$response" | grep -q '"ok":true'; then
            echo "Backup successfully sent to Telegram."
        else
            echo "Error sending backup to Telegram: $response"
        fi
    else
        echo "Telegram bot token or chat ID is not set. Skipping Telegram notification."
    fi
}

backup_volumes() {
    volumes=$(docker volume ls -q)
    ARCHIVE_FILE="${BACKUP_DIR}/FullBackup_${DATE}.tar"
    
    for volume in $volumes; do
        if [ "$volume" = "backup-service_data" ]; then
            echo "Skipping backup for volume $volume."
            continue
        fi

        BACKUP_FILE="${BACKUP_DIR}/backup_${volume}_${DATE}.tar.gz"
        
        docker run --rm -v "$volume":/volume -v backup-service_data:/backup alpine:latest \
            /bin/sh -c "cd /volume && tar -czf /backup/$(basename "$BACKUP_FILE") ."

        if [ ! -f "$BACKUP_FILE" ]; then
            echo "Backup file $BACKUP_FILE was not created. Skipping this volume."
            continue
        fi

        echo "Backup completed for volume ${volume}: ${BACKUP_FILE}"

        tar -rf "$ARCHIVE_FILE" -C "$BACKUP_DIR" "$(basename "$BACKUP_FILE")"
    done

    gzip "$ARCHIVE_FILE"
    echo "Compressed $ARCHIVE_FILE to ${ARCHIVE_FILE}.gz"

    send_telegram "$ARCHIVE_FILE"
}

cleanup_old_backups() {
    find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -exec rm {} \;
    echo "Old backups cleaned up, older than ${RETENTION_DAYS} days"
}

crontab -l | grep -v '/backup-script.sh' | crontab -
echo "${BACKUP_SCHEDULE} /bin/sh /backup-script.sh backup" | crontab -
crond -f -d 8 &


if [ "$1" = "backup" ]; then
    backup_volumes
    cleanup_old_backups
else
    echo "Container started."
    backup_volumes
    echo "Waiting for cron schedule or manual backup trigger."
    tail -f /dev/null
fi
