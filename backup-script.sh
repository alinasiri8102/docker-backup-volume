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

    FILE_SIZE=$(stat -c%s "$archive_file")

    if [ "$FILE_SIZE" -ge $((49 * 1024 * 1024)) ]; then
        echo "📂 Splitting backup because it's larger than 49MB"
        zip -q -s 49m -r "${base_name}.zip" "$archive_file"
    else
        echo "📂 Single-part backup, no split needed"
        zip -q -r "${base_name}.zip" "$archive_file"
    fi

    for part in ${base_name}.zip ${base_name}.z*; do
        [ -f "$part" ] || continue  

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
}

backup_volumes() {
    echo "Taking backups..."

    volumes=$(docker volume ls -q)
    ARCHIVE_FILE="${BACKUP_DIR}/Backup_${DATE}.zip"

    TMP_DIR="${BACKUP_DIR}/tmp_${DATE}"
    mkdir -p "$TMP_DIR"

    for volume in $volumes; do
        if [ "$volume" = "backup-service_data" ]; then
            echo "Skipping backup for volume $volume."
            continue
        fi
        if ! docker run --rm -v "$volume":/data alpine sh -c 'ls -A /data | grep . >/dev/null 2>&1'; then
            echo "Skipping empty volume: $volume"
            continue
        fi

        echo "Creating backup for volume: $volume"
        
        docker run --rm \
            -v "$volume":/source_data \
            -v "$TMP_DIR":/backup_dir \
            alpine sh -c "
                mkdir -p /backup_dir/$volume/_data && \
                cp -a /source_data/. /backup_dir/$volume/_data/
            "
        
        if [ ! -d "$TMP_DIR/$volume/_data" ]; then
            echo "Failed to create backup structure for $volume. Skipping."
            continue
        fi
        
        echo "Backup structure created for volume: $volume"
    done

    echo "Creating final archive..."
    (cd "$TMP_DIR" && zip -r -q "$ARCHIVE_FILE" .)
    
    if [ -f "$ARCHIVE_FILE" ]; then
        echo "📦 Created archive: $ARCHIVE_FILE"
        rm -rf "$TMP_DIR"
        
        send_telegram "$ARCHIVE_FILE"
    else
        echo "❌ Failed to create archive!"
    fi
}

cleanup_old_backups() {
    find "$BACKUP_DIR" -type f -name "*.zip" -mtime +$RETENTION_DAYS -exec rm {} \;
    echo "🗑 Old backups cleaned up, older than ${RETENTION_DAYS} days"
}

echo "🟢 SCRIPT STARTED ON ${DATE}"
backup_volumes
cleanup_old_backups
