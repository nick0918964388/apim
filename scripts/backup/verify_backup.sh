#!/bin/bash
# Kong APIM PostgreSQL 備份完整性驗證腳本

set -euo pipefail

# 配置變數
BACKUP_DIR="/srv/apim/database/backups/daily"
LATEST_BACKUP="${BACKUP_DIR}/kong_full_backup_latest.sql.gz"
TEST_DB_NAME="kong_backup_test"
DB_HOST="localhost"
DB_PORT="5432"
DB_USER="kong"

# 檢查最新備份檔案是否存在
if [ ! -f "${LATEST_BACKUP}" ]; then
    echo "$(date): 錯誤 - 找不到最新備份檔案: ${LATEST_BACKUP}"
    exit 1
fi

echo "$(date): 開始驗證備份完整性 - $(basename ${LATEST_BACKUP})"

# 測試備份檔案結構完整性
if pg_restore --list "${LATEST_BACKUP}" > /dev/null 2>&1; then
    echo "$(date): ✓ 備份檔案結構完整性驗證通過"
else
    echo "$(date): ✗ 錯誤 - 備份檔案結構損壞"
    exit 1
fi

# 創建測試資料庫進行恢復測試
echo "$(date): 創建測試資料庫進行恢復驗證..."

# 刪除可能存在的測試資料庫
PGPASSWORD="${KONG_PG_PASSWORD}" dropdb \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -U "${DB_USER}" \
    "${TEST_DB_NAME}" 2>/dev/null || true

# 創建新的測試資料庫
if PGPASSWORD="${KONG_PG_PASSWORD}" createdb \
    -h "${DB_HOST}" \
    -p "${DB_PORT}" \
    -U "${DB_USER}" \
    "${TEST_DB_NAME}"; then
    
    echo "$(date): ✓ 測試資料庫創建成功"
    
    # 恢復備份到測試資料庫
    if PGPASSWORD="${KONG_PG_PASSWORD}" pg_restore \
        -h "${DB_HOST}" \
        -p "${DB_PORT}" \
        -U "${DB_USER}" \
        -d "${TEST_DB_NAME}" \
        --verbose \
        --clean \
        "${LATEST_BACKUP}" 2>/dev/null; then
        
        echo "$(date): ✓ 備份恢復測試成功"
        
        # 檢查恢復的數據完整性
        TABLE_COUNT=$(PGPASSWORD="${KONG_PG_PASSWORD}" psql \
            -h "${DB_HOST}" \
            -p "${DB_PORT}" \
            -U "${DB_USER}" \
            -d "${TEST_DB_NAME}" \
            -t -c "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public';" | tr -d ' ')
        
        if [ "${TABLE_COUNT}" -gt 0 ]; then
            echo "$(date): ✓ 數據完整性驗證通過 - 找到 ${TABLE_COUNT} 個資料表"
            
            # 清理測試資料庫
            PGPASSWORD="${KONG_PG_PASSWORD}" dropdb \
                -h "${DB_HOST}" \
                -p "${DB_PORT}" \
                -U "${DB_USER}" \
                "${TEST_DB_NAME}"
            
            echo "$(date): ✓ 備份完整性驗證完成 - 所有測試通過"
            exit 0
        else
            echo "$(date): ✗ 錯誤 - 恢復的資料庫沒有找到資料表"
            exit 1
        fi
    else
        echo "$(date): ✗ 錯誤 - 備份恢復失敗"
        exit 1
    fi
else
    echo "$(date): ✗ 錯誤 - 測試資料庫創建失敗"
    exit 1
fi