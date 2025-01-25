#!/bin/sh

BACKUP_DIR="/backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +"%Y-%m-%d_%H-%M-%S")
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-14}

send_telegram() {
    local archive_file=$1
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        curl_cmd="curl -s -X POST \"https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument\" \
            -F chat_id=\"${TELEGRAM_CHAT_ID}\" \
            -F document=\"@${archive_file}\" \
            -F caption=\"📌 $DATE\""
        
        if [ -n "$TELEGRAM_THREAD_ID" ]; then
            curl_cmd="$curl_cmd -F message_thread_id=\"${TELEGRAM_THREAD_ID}\""
        fi
        response=$(eval "$curl_cmd")
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
    echo "Taking backups..."

    volumes=$(docker volume ls -q)
    ARCHIVE_FILE="${BACKUP_DIR}/FullBackup_${DATE}.tar"
    
    for volume in $volumes; do
        if [ "$volume" = "backup-service_data" ]; then
            echo "skipping backup for volume $volume."
            continue
        fi

        BACKUP_FILE="${BACKUP_DIR}/${volume}.tar.gz"

        docker run --rm -v "${volume}:/volume" -v backup-service_data:/backup alpine:latest \
            /bin/sh -c "tar -czf /backup/$(basename "$BACKUP_FILE") -C / volume"

        if [ ! -f "$BACKUP_FILE" ]; then
            echo "backup file $BACKUP_FILE was not created. Skipping this volume."
            continue
        fi

        echo "backup completed for volume ${volume}: ${BACKUP_FILE}"

        tar -rf "$ARCHIVE_FILE" -C "$BACKUP_DIR" "$(basename "$BACKUP_FILE")"
    done

    gzip "$ARCHIVE_FILE"
    echo "compressed $ARCHIVE_FILE to ${ARCHIVE_FILE}.gz"

    send_telegram "${ARCHIVE_FILE}.gz"
}

cleanup_old_backups() {
    find "$BACKUP_DIR" -type f -name "*.tar.gz" -mtime +$RETENTION_DAYS -exec rm {} \;
    echo "Old backups cleaned up, older than ${RETENTION_DAYS} days"
}

echo "SCRIPT STARTED ON ${DATE}"
backup_volumes
cleanup_old_backups


