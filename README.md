# Docker Volume Backup Service

## Overview

This Docker service automates the process of backing up Docker volumes. It creates compressed backups of the volumes, retains them for a specified number of days, and sends notifications via Telegram upon successful backup completion. This service is particularly useful for maintaining data integrity and ensuring that important data is not lost.

## Features

- Automated backups of Docker volumes.
- Notification of backup completion sent to Telegram.
- Scheduled backups using Cron.
- Retention policy to automatically delete old backups.

## Requirements

- Docker
- A Telegram bot token and chat ID for notifications.

## Usage

1. **Clone the repository** or create a Docker Compose file using the provided configuration.

2. **Set environment variables** for your Telegram bot token and chat ID, as well as backup schedule and retention days.

3. **Run the service** with Docker Compose:

   ```bash
   docker-compose up -d
   ```

## Environment Variables

| Variable                | Description                                                                                                                                                 |
| ----------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `TELEGRAM_BOT_TOKEN`    | The authentication token for your Telegram bot. You can obtain this token by creating a new bot with [BotFather](https://core.telegram.org/bots#botfather). |
| `TELEGRAM_CHAT_ID`      | The chat ID where backup notifications will be sent. You can get this ID by messaging your bot and checking the response.                                   |
| `BACKUP_SCHEDULE`       | The cron schedule for automated backup execution (in UTC). For example, `"0 2,6 * * *"` runs backups daily at 2 AM and 6 AM.                                |
| `BACKUP_RETENTION_DAYS` | The number of days to retain backups before deletion. For example, if set to `3`, backups older than 3 days will be automatically removed.                  |

## Backup Process

- The backup script is executed based on the specified cron schedule.
- Upon execution, all Docker volumes are backed up into a specified directory (`/backups`).
- Each backup is compressed into a `.tar.gz` file and moved to the designated backup directory.
- After successful backup creation, a notification with the backup details is sent to the specified Telegram chat.

## Cleanup Process

- The service automatically cleans up backups older than the specified retention period during each backup execution.

## Conclusion

This Docker Volume Backup Service simplifies the backup process of Docker volumes and ensures that you are notified of any successful backups. By customizing the environment variables, you can tailor the service to fit your specific backup requirements.

For any issues or contributions, please feel free to open an issue or pull request.
