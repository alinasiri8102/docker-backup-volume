#!/bin/sh

BACKUP_DIR="/backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +"%Y-%m-%d_%H-%M-%S")
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-14}

send_telegram() {
    local archive_file=$1
    local max_size=$((49 * 1024 * 1024))  # 49MB max per part
    local base_name=$DATE

    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo "Telegram bot token or chat ID is missing. Skipping."
        return
    fi

    file_size=$(stat -c%s "$archive_file")

    if (( file_size > max_size )); then
        echo "File is larger than 50MB. Splitting..."
        split -b $max_size -d --additional-suffix=".part" "$archive_file" "${archive_file}."

        for part in ${archive_file}.*.part; do
            curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
                -F chat_id="$TELEGRAM_CHAT_ID" \
                -F document="@$part" \
                -F caption="📌 ${base_name} - ${$part}" \
                ${TELEGRAM_THREAD_ID:+-F message_thread_id="$TELEGRAM_THREAD_ID"} > /dev/null
            rm -f "$part"
        done
    else
        curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F chat_id="$TELEGRAM_CHAT_ID" \
            -F document="@$archive_file" \
            -F caption="📌 ${base_name}" \
            ${TELEGRAM_THREAD_ID:+-F message_thread_id="$TELEGRAM_THREAD_ID"} > /dev/null
    fi

    echo "Backup sent to Telegram."
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
        
        docker run --rm -v "$volume":/volume/$volume/_data -v backup-service_data:/backup alpine:latest \
            /bin/sh -c "cd /volume && tar -czf /backup/$(basename "$BACKUP_FILE") ."

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

