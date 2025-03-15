#!/bin/sh

BACKUP_DIR="/backups"
mkdir -p "$BACKUP_DIR"

DATE=$(date +"%Y-%m-%d_%H-%M-%S")
RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-14}

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo "❌ Telegram bot token or chat ID is missing. Exiting."
    exit 1
fi

send_telegram() {
    local archive_file=$1
    local base_name="backup_$(date +%Y-%m-%d)"

    zip -q -s 49m -r "${base_name}.zip" "$archive_file"

    # Check if the file was split into parts
    if ls ${base_name}.z* >/dev/null 2>&1; then
        # Handle multi-part files
        for part in ${base_name}.z*; do
            if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
                -F chat_id="$TELEGRAM_CHAT_ID" \
                -F document="@$part" \
                -F caption="$(basename "$part")" \
                ${TELEGRAM_THREAD_ID:+-F message_thread_id="$TELEGRAM_THREAD_ID"} > /dev/null; then
                rm -f "$part"
                echo "✅ Backup $part sent to Telegram."
            else
                echo "❌ Failed to send $part!"
            fi
        done
    else
        # Handle single file
        if curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendDocument" \
            -F chat_id="$TELEGRAM_CHAT_ID" \
            -F document="@${base_name}.zip" \
            -F caption="$(basename "${base_name}.zip")" \
            ${TELEGRAM_THREAD_ID:+-F message_thread_id="$TELEGRAM_THREAD_ID"} > /dev/null; then
            rm -f "${base_name}.zip"
            echo "✅ Backup ${base_name}.zip sent to Telegram."
        else
            echo "❌ Failed to send ${base_name}.zip!"
        fi
    fi
}

backup_volumes() {
    echo "Taking backups..."

    volumes=$(docker volume ls -q)
    ARCHIVE_FILE="${BACKUP_DIR}/Backup_${DATE}.zip"

    for volume in $volumes; do
        if [ "$volume" = "backup-service_data" ]; then
            echo "Skipping backup for volume $volume."
            continue
        fi
        if ! docker run --rm -v "$volume":/data alpine sh -c 'ls -A /data | grep . >/dev/null 2>&1'; then
            echo "Skipping empty volume: $volume"
            continue
        fi

        BACKUP_FILE="${BACKUP_DIR}/${volume}.zip"

        docker run --rm -v "$volume":/data -v backup-service_data:/backup volume_backup \
            /bin/sh -c "cd /data && zip -q -r /backup/$(basename "$BACKUP_FILE") ."

        if [ ! -f "$BACKUP_FILE" ]; then
            echo "Backup file $BACKUP_FILE was not created. Skipping this volume."
            continue
        fi

        echo "Backup completed for volume ${volume}: ${BACKUP_FILE}"

        zip -r -q "$ARCHIVE_FILE" "$BACKUP_FILE"
    done

    echo "📦 Created archive: $ARCHIVE_FILE"

    send_telegram "$ARCHIVE_FILE"
}

cleanup_old_backups() {
    find "$BACKUP_DIR" -type f -name "*.zip" -mtime +$RETENTION_DAYS -exec rm {} \;
    echo "🗑 Old backups cleaned up, older than ${RETENTION_DAYS} days"
}

echo "🟢 SCRIPT STARTED ON ${DATE}"
backup_volumes
cleanup_old_backups
