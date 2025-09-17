#!/bin/bash
# Kong APIM PostgreSQL 增量備份腳本
# 每小時執行 WAL 檔案備份

set -euo pipefail

# 配置變數
DB_HOST="localhost"
DB_PORT="5432"
DB_USER="kong"
WAL_ARCHIVE_DIR="/srv/apim/database/backups/wal_archive"
INCREMENTAL_DIR="/srv/apim/database/backups/hourly"
BACKUP_RETENTION_DAYS=7
DATE=$(date +%Y%m%d_%H%M%S)

# 建立備份目錄
mkdir -p "${WAL_ARCHIVE_DIR}" "${INCREMENTAL_DIR}"

# 記錄備份開始
echo "$(date): 開始執行 Kong 資料庫增量備份" >> "${INCREMENTAL_DIR}/incremental.log"

# 強制 WAL 切換以確保當前事務被備份
if PGPASSWORD="${KONG_PG_PASSWORD}" psql \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    -c "SELECT pg_switch_wal();" > /dev/null; then
    
    echo "$(date): WAL 切換成功" >> "${INCREMENTAL_DIR}/incremental.log"
    
    # 複製新的 WAL 檔案到增量備份目錄
    if [ -d "${WAL_ARCHIVE_DIR}" ]; then
        INCREMENTAL_FILE="${INCREMENTAL_DIR}/wal_backup_${DATE}.tar.gz"
        tar -czf "${INCREMENTAL_FILE}" -C "${WAL_ARCHIVE_DIR}" . --newer-mtime='1 hour ago' 2>/dev/null || true
        
        if [ -f "${INCREMENTAL_FILE}" ]; then
            echo "$(date): 增量備份成功 - wal_backup_${DATE}.tar.gz" >> "${INCREMENTAL_DIR}/incremental.log"
        else
            echo "$(date): 警告 - 沒有新的 WAL 檔案需要備份" >> "${INCREMENTAL_DIR}/incremental.log"
        fi
    fi
    
    # 清理過期增量備份
    find "${INCREMENTAL_DIR}" -name "wal_backup_*.tar.gz" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete
    
    echo "$(date): 增量備份清理完成，保留 ${BACKUP_RETENTION_DAYS} 天" >> "${INCREMENTAL_DIR}/incremental.log"
    
else
    echo "$(date): 錯誤 - WAL 切換失敗" >> "${INCREMENTAL_DIR}/incremental.log"
    exit 1
fi