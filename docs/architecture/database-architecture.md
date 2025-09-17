# 資料庫架構 (Database Architecture)

## PostgreSQL 高可用性設計 (PostgreSQL High Availability Design)

### 架構概覽 (Architecture Overview)

```
┌─────────────────┐    ┌─────────────────┐
│   Kong Gateway  │────│  Load Balancer  │
└─────────────────┘    └─────────────────┘
         │                       │
         ├─── Write ──────────────┤
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌─────────────────┐
│  PostgreSQL     │────│  PostgreSQL     │
│  Master         │    │  Slave          │
│  (Read/Write)   │────│  (Read Only)    │
│  Port: 5432     │    │  Port: 5433     │
└─────────────────┘    └─────────────────┘
         │                       │
         ▼                       ▼
┌─────────────────┐    ┌─────────────────┐
│  Master Storage │    │  Slave Storage  │
│ /srv/apim/      │    │ /srv/apim/      │
│ database/master │    │ database/slave  │
└─────────────────┘    └─────────────────┘
         │
         ▼
┌─────────────────┐
│  Backup Storage │
│ /srv/apim/      │
│ database/       │
│ backups/        │
└─────────────────┘
```

## 主從複製配置 (Master-Slave Replication Configuration)

### 主資料庫配置 (Master Database Configuration)

#### postgresql.conf 設置
```ini
# 複製相關設置
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 128MB
hot_standby = on

# 歸檔設置
archive_mode = on
archive_command = 'test ! -f /srv/apim/database/backups/wal_archive/%f && cp %p /srv/apim/database/backups/wal_archive/%f'
archive_timeout = 300

# 記憶體設置
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB

# 連接設置
max_connections = 200
listen_addresses = '*'
port = 5432

# 日誌設置
logging_collector = on
log_directory = 'log'
log_filename = 'postgresql-%Y-%m-%d_%H%M%S.log'
log_min_duration_statement = 1000
log_line_prefix = '%t [%p]: [%l-1] user=%u,db=%d,app=%a,client=%h '
log_checkpoints = on
log_connections = on
log_disconnections = on
log_lock_waits = on

# 檢查點設置
checkpoint_timeout = 5min
checkpoint_completion_target = 0.7
max_wal_size = 1GB
min_wal_size = 80MB
```

#### pg_hba.conf 設置
```ini
# 本地連接
local   all             postgres                                trust
local   all             kong                                    md5

# IPv4 本地連接
host    all             postgres        127.0.0.1/32            trust
host    all             kong            127.0.0.1/32            md5

# Kong 應用連接
host    kong            kong            172.0.0.0/8             md5

# 複製連接
host    replication     replicator      172.0.0.0/8             md5
host    replication     replicator      0.0.0.0/0               md5

# 所有其他連接
host    all             all             0.0.0.0/0               md5
```

### 從資料庫配置 (Slave Database Configuration)

#### postgresql.conf 設置
```ini
# 基本設置 (繼承主庫大部分設置)
wal_level = replica
max_wal_senders = 10
max_replication_slots = 10
wal_keep_size = 128MB

# 熱備用設置
hot_standby = on
max_standby_archive_delay = 30s
max_standby_streaming_delay = 30s
wal_receiver_status_interval = 10s
hot_standby_feedback = on

# 記憶體設置
shared_buffers = 256MB
effective_cache_size = 1GB
work_mem = 4MB
maintenance_work_mem = 64MB

# 連接設置
max_connections = 200
listen_addresses = '*'
port = 5432

# 複製設置
primary_conninfo = 'host=kong-database-master port=5432 user=replicator password=replicator_password application_name=kong_slave'
primary_slot_name = 'kong_slave_slot'
promote_trigger_file = '/tmp/postgresql.trigger.5432'
```

## 存儲管理 (Storage Management)

### 目錄結構設計 (Directory Structure Design)

```bash
/srv/apim/database/
├── master/                          # 主資料庫數據目錄
│   ├── base/                       # 資料庫基礎文件
│   │   ├── 1/                      # 模板資料庫
│   │   ├── 13395/                  # template0
│   │   ├── 13396/                  # template1
│   │   └── 16384/                  # kong 資料庫
│   ├── global/                     # 全域系統表
│   ├── pg_wal/                     # WAL 日誌文件
│   │   ├── 000000010000000000000001
│   │   ├── 000000010000000000000002
│   │   └── archive_status/
│   ├── pg_logical/                 # 邏輯複製
│   ├── pg_replslot/               # 複製插槽
│   ├── pg_stat/                   # 統計信息
│   ├── pg_stat_tmp/               # 臨時統計文件
│   ├── pg_tblspc/                 # 表空間
│   ├── log/                       # PostgreSQL 日誌
│   ├── postgresql.conf            # 主要配置文件
│   ├── pg_hba.conf               # 認證配置
│   ├── pg_ident.conf             # 身份映射
│   └── postmaster.pid            # 進程 ID 文件
├── slave/                          # 從資料庫數據目錄
│   ├── base/                      # 複製的資料庫文件
│   ├── global/
│   ├── pg_wal/
│   ├── recovery.signal            # 恢復模式標識
│   ├── standby.signal             # 備用模式標識
│   ├── postgresql.conf
│   ├── pg_hba.conf
│   └── log/
├── backups/                        # 備份存儲目錄
│   ├── daily/                     # 每日完整備份
│   │   ├── kong_full_backup_20250917_020000.dump.gz
│   │   ├── kong_full_backup_20250916_020000.dump.gz
│   │   └── ...
│   ├── hourly/                    # 每小時增量備份
│   │   ├── kong_incr_backup_20250917_140000.dump
│   │   ├── kong_incr_backup_20250917_130000.dump
│   │   └── ...
│   ├── wal_archive/               # WAL 歸檔
│   │   ├── 000000010000000000000001
│   │   ├── 000000010000000000000002
│   │   └── ...
│   └── scripts/                   # 備份腳本
│       ├── full_backup.sh
│       ├── incremental_backup.sh
│       └── cleanup_old_backups.sh
└── config/                         # 配置文件模板
    ├── master.conf                # 主庫特定配置
    ├── slave.conf                 # 從庫特定配置
    ├── pg_hba_master.conf         # 主庫認證配置模板
    └── pg_hba_slave.conf          # 從庫認證配置模板
```

### 磁碟空間管理 (Disk Space Management)

#### 容量規劃 (Capacity Planning)
```yaml
storage_requirements:
  master_database:
    initial_size: "5GB"
    growth_rate: "1GB/month"
    recommended_free_space: "50%"
    
  slave_database:
    size: "same as master"
    sync_lag_buffer: "10%"
    
  wal_storage:
    retention_size: "10GB"
    max_wal_size: "2GB"
    
  backup_storage:
    daily_backups: "30 × average_db_size"
    hourly_backups: "168 × incremental_size" 
    wal_archive: "14 days × wal_generation_rate"
    total_recommendation: "100GB minimum"

disk_monitoring:
  warning_threshold: "80%"
  critical_threshold: "90%"
  cleanup_trigger: "85%"
```

## 備份策略 (Backup Strategy)

### 多層備份機制 (Multi-tier Backup Mechanism)

#### 1. 即時複製 (Real-time Replication)
- **目的**: 零數據丟失，即時故障轉移
- **方法**: 流式複製 (Streaming Replication)
- **延遲**: < 1秒
- **恢復點**: 即時

#### 2. WAL 歸檔 (WAL Archiving)
- **目的**: 點時間恢復 (PITR)
- **方法**: 連續歸檔和恢復
- **保留期**: 14天
- **顆粒度**: 事務級別

#### 3. 完整備份 (Full Backup)
- **頻率**: 每日 02:00
- **方法**: pg_dump (邏輯備份)
- **格式**: Custom format + gzip 壓縮
- **保留期**: 30天
- **驗證**: 自動恢復測試

#### 4. 增量備份 (Incremental Backup)
- **頻率**: 每小時
- **方法**: pg_receivewal
- **保留期**: 7天
- **用途**: 快速恢復近期變更

### 備份腳本集合 (Backup Script Collection)

#### 完整備份腳本 (Full Backup Script)
```bash
#!/bin/bash
# /srv/apim/database/backups/scripts/full_backup.sh

set -euo pipefail

# 配置變數
BACKUP_DIR="/srv/apim/database/backups/daily"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATABASE_HOST="kong-database-master"
DATABASE_NAME="kong"
DATABASE_USER="kong"
LOG_FILE="/var/log/kong-backup.log"
RETENTION_DAYS=30

# 創建備份目錄
mkdir -p "$BACKUP_DIR"

# 記錄開始時間
echo "$(date): Starting full backup of Kong database" >> "$LOG_FILE"

# 執行完整備份
BACKUP_FILE="$BACKUP_DIR/kong_full_backup_$TIMESTAMP.dump"
pg_dump -h "$DATABASE_HOST" -U "$DATABASE_USER" -d "$DATABASE_NAME" \
    --verbose --clean --create --format=custom \
    --file="$BACKUP_FILE" 2>> "$LOG_FILE"

# 壓縮備份文件
gzip "$BACKUP_FILE"
COMPRESSED_FILE="$BACKUP_FILE.gz"

# 驗證備份文件
if [ -f "$COMPRESSED_FILE" ] && [ -s "$COMPRESSED_FILE" ]; then
    echo "$(date): Full backup completed successfully: $COMPRESSED_FILE" >> "$LOG_FILE"
    
    # 測試備份完整性
    pg_restore --list "$COMPRESSED_FILE" > /dev/null 2>> "$LOG_FILE"
    if [ $? -eq 0 ]; then
        echo "$(date): Backup integrity verified" >> "$LOG_FILE"
    else
        echo "$(date): WARNING: Backup integrity check failed" >> "$LOG_FILE"
    fi
else
    echo "$(date): ERROR: Full backup failed" >> "$LOG_FILE"
    exit 1
fi

# 清理舊備份
find "$BACKUP_DIR" -name "kong_full_backup_*.dump.gz" -mtime +$RETENTION_DAYS -delete
echo "$(date): Cleaned up backups older than $RETENTION_DAYS days" >> "$LOG_FILE"

# 報告備份大小和統計
BACKUP_SIZE=$(du -h "$COMPRESSED_FILE" | cut -f1)
echo "$(date): Backup size: $BACKUP_SIZE" >> "$LOG_FILE"

echo "$(date): Full backup process completed" >> "$LOG_FILE"
```

#### 增量備份腳本 (Incremental Backup Script)
```bash
#!/bin/bash
# /srv/apim/database/backups/scripts/incremental_backup.sh

set -euo pipefail

# 配置變數
BACKUP_DIR="/srv/apim/database/backups/hourly"
WAL_DIR="/srv/apim/database/backups/wal_archive"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATABASE_HOST="kong-database-master"
REPLICATION_USER="replicator"
LOG_FILE="/var/log/kong-backup.log"
RETENTION_HOURS=168  # 7 days

# 創建備份目錄
mkdir -p "$BACKUP_DIR"
mkdir -p "$WAL_DIR"

echo "$(date): Starting incremental backup" >> "$LOG_FILE"

# 執行 WAL 歸檔備份
pg_receivewal -h "$DATABASE_HOST" -U "$REPLICATION_USER" \
    -D "$WAL_DIR" --synchronous --verbose \
    >> "$LOG_FILE" 2>&1 &

RECEIVEWAL_PID=$!

# 運行5分鐘後停止
sleep 300
kill $RECEIVEWAL_PID 2>/dev/null || true

# 創建當前時間點的標記文件
echo "Incremental backup completed at $(date)" > "$BACKUP_DIR/incr_backup_$TIMESTAMP.marker"

# 清理舊的增量備份標記
find "$BACKUP_DIR" -name "incr_backup_*.marker" -mmin +$((RETENTION_HOURS * 60)) -delete

# 清理舊的 WAL 文件 (保留14天)
find "$WAL_DIR" -name "0*" -mtime +14 -delete

echo "$(date): Incremental backup completed" >> "$LOG_FILE"
```

#### 自動化備份調度 (Automated Backup Scheduling)
```bash
# /etc/cron.d/kong-database-backup

# 每日完整備份 (凌晨2點)
0 2 * * * root /srv/apim/database/backups/scripts/full_backup.sh

# 每小時增量備份
0 * * * * root /srv/apim/database/backups/scripts/incremental_backup.sh

# 每週清理日誌文件
0 3 * * 0 root /srv/apim/database/backups/scripts/cleanup_logs.sh

# 每月備份驗證
0 4 1 * * root /srv/apim/database/backups/scripts/verify_backups.sh
```

## 恢復程序 (Recovery Procedures)

### 災難恢復場景 (Disaster Recovery Scenarios)

#### 場景1: 主資料庫故障
```bash
#!/bin/bash
# 主資料庫故障轉移程序

echo "Detecting master database failure..."

# 1. 確認主庫故障
if ! pg_isready -h kong-database-master -p 5432; then
    echo "Master database is down. Initiating failover..."
    
    # 2. 提升從庫為主庫
    docker exec kong-database-slave touch /tmp/postgresql.trigger.5432
    
    # 3. 等待從庫提升完成
    sleep 10
    
    # 4. 更新 Kong 配置指向新主庫
    docker exec kong kong config set pg_host kong-database-slave
    docker restart kong
    
    # 5. 驗證新主庫可用性
    if pg_isready -h kong-database-slave -p 5432; then
        echo "Failover completed successfully"
    else
        echo "Failover failed"
        exit 1
    fi
fi
```

#### 場景2: 點時間恢復 (Point-in-Time Recovery)
```bash
#!/bin/bash
# 點時間恢復程序

RECOVERY_TARGET_TIME="$1"  # 格式: '2025-09-17 14:30:00'
BACKUP_FILE="$2"           # 完整備份文件路徑

if [ -z "$RECOVERY_TARGET_TIME" ] || [ -z "$BACKUP_FILE" ]; then
    echo "Usage: $0 'YYYY-MM-DD HH:MM:SS' backup_file.dump.gz"
    exit 1
fi

echo "Starting point-in-time recovery to $RECOVERY_TARGET_TIME"

# 1. 停止所有相關服務
docker-compose down

# 2. 清理現有數據目錄
sudo rm -rf /srv/apim/database/master/*
sudo rm -rf /srv/apim/database/slave/*

# 3. 恢復完整備份
echo "Restoring full backup..."
gunzip -c "$BACKUP_FILE" | pg_restore -h localhost -U kong -d kong --clean --create --verbose

# 4. 配置恢復參數
cat > /srv/apim/database/master/recovery.conf << EOF
restore_command = 'cp /srv/apim/database/backups/wal_archive/%f %p'
recovery_target_time = '$RECOVERY_TARGET_TIME'
recovery_target_action = 'promote'
EOF

# 5. 啟動資料庫進行恢復
docker-compose up kong-database-master

echo "Point-in-time recovery completed"
```

## 監控與維護 (Monitoring & Maintenance)

### 資料庫效能監控 (Database Performance Monitoring)

#### 關鍵指標 (Key Metrics)
```sql
-- 1. 複製延遲監控
SELECT 
    client_addr,
    application_name,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    write_lag,
    flush_lag,
    replay_lag,
    sync_state,
    sync_priority
FROM pg_stat_replication;

-- 2. 資料庫連接監控
SELECT 
    datname,
    numbackends,
    xact_commit,
    xact_rollback,
    blks_read,
    blks_hit,
    tup_returned,
    tup_fetched,
    tup_inserted,
    tup_updated,
    tup_deleted
FROM pg_stat_database 
WHERE datname = 'kong';

-- 3. 慢查詢監控
SELECT 
    query,
    calls,
    total_time,
    mean_time,
    stddev_time,
    rows
FROM pg_stat_statements 
WHERE mean_time > 1000  -- 超過1秒的查詢
ORDER BY mean_time DESC;

-- 4. 磁碟空間使用
SELECT 
    schemaname,
    tablename,
    pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) as size
FROM pg_tables 
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

#### 自動維護腳本 (Automated Maintenance Scripts)
```bash
#!/bin/bash
# /srv/apim/database/backups/scripts/maintenance.sh

# 執行 VACUUM ANALYZE
psql -h kong-database-master -U kong -d kong -c "VACUUM ANALYZE;"

# 重建索引統計
psql -h kong-database-master -U kong -d kong -c "REINDEX DATABASE kong;"

# 清理過期的連接
psql -h kong-database-master -U kong -d kong -c "
SELECT pg_terminate_backend(pid) 
FROM pg_stat_activity 
WHERE datname = 'kong' 
  AND state = 'idle' 
  AND state_change < now() - interval '1 hour';"

echo "Database maintenance completed at $(date)"
```

### 告警配置 (Alert Configuration)

#### Kibana 資料庫監控儀表板
```json
{
  "database_monitoring_dashboard": {
    "panels": [
      {
        "title": "複製延遲",
        "type": "line_chart",
        "query": "SELECT replay_lag FROM pg_stat_replication",
        "threshold": "5 seconds"
      },
      {
        "title": "活躍連接數",
        "type": "gauge",
        "query": "SELECT count(*) FROM pg_stat_activity WHERE state = 'active'",
        "warning": 150,
        "critical": 180
      },
      {
        "title": "磁碟使用率",
        "type": "progress_bar",
        "query": "df -h /srv/apim/database",
        "warning": "80%",
        "critical": "90%"
      },
      {
        "title": "備份狀態",
        "type": "status_indicator",
        "source": "/var/log/kong-backup.log",
        "success_pattern": "backup completed successfully",
        "failure_pattern": "backup failed"
      }
    ]
  }
}
```

這個詳細的資料庫架構文檔涵蓋了 PostgreSQL 主從架構的完整實現，包括配置、存儲管理、備份策略和恢復程序。