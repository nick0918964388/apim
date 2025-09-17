#!/bin/bash
# Kong APIM PostgreSQL 完整備份腳本
# 每日 02:00 執行完整備份

set -euo pipefail

# 配置變數
DB_HOST="localhost"
DB_PORT="5432"
DB_NAME="kong"
DB_USER="kong"
BACKUP_DIR="/srv/apim/database/backups/daily"
BACKUP_RETENTION_DAYS=30
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="kong_full_backup_${DATE}.sql.gz"

# 建立備份目錄
mkdir -p "${BACKUP_DIR}"

# 記錄備份開始
echo "$(date): 開始執行 Kong 資料庫完整備份" >> "${BACKUP_DIR}/backup.log"

# 執行完整備份
if PGPASSWORD="${KONG_PG_PASSWORD}" pg_dump \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -U "${DB_USER}" \
    -d "${DB_NAME}" \
    --verbose \
    --format=custom \
    --compress=9 \
    --file="${BACKUP_DIR}/${BACKUP_FILE}"; then
    
    echo "$(date): 完整備份成功 - ${BACKUP_FILE}" >> "${BACKUP_DIR}/backup.log"
    
    # 建立最新備份的軟連結
    ln -sf "${BACKUP_FILE}" "${BACKUP_DIR}/kong_full_backup_latest.sql.gz"
    
    # 清理過期備份
    find "${BACKUP_DIR}" -name "kong_full_backup_*.sql.gz" -type f -mtime +${BACKUP_RETENTION_DAYS} -delete
    
    echo "$(date): 備份清理完成，保留 ${BACKUP_RETENTION_DAYS} 天" >> "${BACKUP_DIR}/backup.log"
    
else
    echo "$(date): 錯誤 - 完整備份失敗" >> "${BACKUP_DIR}/backup.log"
    exit 1
fi