#!/bin/bash
# PostgreSQL Slave 初始化腳本

set -e

echo "Checking if this is a fresh slave setup..."

# 檢查是否為新的 slave 節點
if [ ! -s "$PGDATA/PG_VERSION" ]; then
    echo "Fresh PostgreSQL slave detected. Setting up replication..."
    
    # 等待 master 就緒
    echo "Waiting for master database to be ready..."
    until PGPASSWORD="$POSTGRES_REPLICATION_PASSWORD" pg_isready -h kong-database-master -U "$POSTGRES_REPLICATION_USER"
    do
        echo "Master database is unavailable - sleeping"
        sleep 2
    done
    
    echo "Master database is ready. Starting pg_basebackup..."
    
    # 執行 basebackup
    PGPASSWORD="$POSTGRES_REPLICATION_PASSWORD" pg_basebackup \
        -h kong-database-master \
        -D "$PGDATA" \
        -U "$POSTGRES_REPLICATION_USER" \
        -W -v -P
    
    # 設定 primary connection info
    echo "primary_conninfo = 'host=kong-database-master port=5432 user=$POSTGRES_REPLICATION_USER password=$POSTGRES_REPLICATION_PASSWORD'" >> "$PGDATA/postgresql.auto.conf"
    
    # 創建 standby signal 文件
    touch "$PGDATA/standby.signal"
    
    echo "PostgreSQL slave setup completed."
else
    echo "Existing PostgreSQL data found. Skipping slave setup."
fi