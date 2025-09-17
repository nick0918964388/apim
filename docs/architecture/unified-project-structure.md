# 統一專案結構 (Unified Project Structure)

## 專案根目錄結構 (Root Directory Structure)

```
apim/
├── docs/                          # 專案文件
│   ├── prd.md                    # 產品需求文件
│   ├── architecture/             # 架構文件
│   │   ├── backend-architecture.md
│   │   ├── database-architecture.md
│   │   ├── data-models.md
│   │   ├── tech-stack.md
│   │   ├── unified-project-structure.md
│   │   ├── coding-standards.md
│   │   └── testing-strategy.md
│   └── stories/                  # 用戶故事文件
├── deployments/                  # 部署配置
│   ├── docker/                   # Docker 配置
│   │   ├── docker-compose.yml   # 主要編排文件
│   │   ├── docker-compose.dev.yml
│   │   └── docker-compose.prod.yml
│   ├── kong/                     # Kong 配置文件
│   │   └── declarative/          # 宣告式配置
│   └── monitoring/               # 監控配置
│       ├── elasticsearch/        # ES 配置
│       ├── logstash/             # Logstash 配置
│       │   └── kong-logs.conf
│       └── kibana/               # Kibana 配置
├── config/                       # 設定檔案
│   ├── kong/                     # Kong 設定
│   │   └── kong.conf
│   ├── postgresql/               # PostgreSQL 設定
│   │   ├── master/               # 主庫配置
│   │   │   ├── postgresql.conf
│   │   │   └── pg_hba.conf
│   │   └── slave/                # 從庫配置
│   │       ├── postgresql.conf
│   │       └── pg_hba.conf
│   └── env/                      # 環境變數
│       ├── .env.dev
│       ├── .env.test
│       └── .env.prod
├── scripts/                      # 自動化腳本
│   ├── setup/                    # 安裝設定腳本
│   ├── postgresql/               # PostgreSQL 腳本
│   │   ├── init-replication.sql
│   │   └── setup-permissions.sh
│   ├── backup/                   # 備份腳本
│   │   ├── full_backup.sh
│   │   ├── incremental_backup.sh
│   │   ├── verify_backup.sh
│   │   └── cleanup_old_backups.sh
│   └── monitoring/               # 監控腳本
│       ├── health_check.sh
│       └── alert_check.sh
├── tests/                        # 測試文件
│   ├── integration/              # 整合測試
│   │   ├── kong_postgres_test.sh
│   │   └── elk_integration_test.sh
│   ├── api/                      # API 測試
│   │   └── postman_collections/
│   ├── performance/              # 效能測試
│   │   └── load_tests/
│   └── backup/                   # 備份測試
│       └── restore_test.sh
└── .bmad-core/                   # BMad 專案管理核心
    ├── core-config.yaml          # 核心配置
    ├── tasks/                    # 任務模板
    ├── templates/                # 故事模板
    └── checklists/               # 檢查清單
```

## 配置目錄詳細說明 (Configuration Details)

### Kong 配置結構 (Kong Configuration Structure)
```
config/kong/
├── kong.conf                     # Kong 主配置文件
├── plugins/                      # 自定義插件配置
├── services/                     # 服務定義
├── routes/                       # 路由定義
└── consumers/                    # 消費者配置
```

### 部署配置結構 (Deployment Configuration Structure)
```
deployments/
├── docker/
│   ├── docker-compose.yml        # 主要編排文件
│   ├── docker-compose.dev.yml    # 開發環境
│   ├── docker-compose.prod.yml   # 生產環境
│   └── Dockerfile                # Kong 自定義映像檔
├── kong/
│   ├── declarative/              # 宣告式配置文件
│   └── migrations/               # 資料庫遷移腳本
└── monitoring/
    ├── elasticsearch/            # ES 配置
    ├── logstash/                 # Logstash 配置
    └── kibana/                   # Kibana 配置
```

## 檔案命名規範 (File Naming Conventions)

### 配置檔案 (Configuration Files)
- Kong 服務: `{service-name}.service.yml`
- Kong 路由: `{route-name}.route.yml`
- Docker 配置: `docker-compose.{env}.yml`
- 環境變數: `.env.{environment}`

### 腳本檔案 (Script Files)
- 設定腳本: `setup-{component}.sh`
- 備份腳本: `backup-{component}-{timestamp}.sh`
- 監控腳本: `monitor-{metric}.sh`

### 測試檔案 (Test Files)
- API 測試: `test-{api-name}.{format}` (postman/newman)
- 整合測試: `integration-test-{scenario}.sh`
- 效能測試: `performance-{component}.yml`

## 主機存儲結構 (Host Storage Structure)

### PostgreSQL 數據存儲 (PostgreSQL Data Storage)
```bash
/srv/apim/database/
├── master/                        # 主資料庫數據目錄
│   ├── base/                     # 資料庫文件
│   │   ├── 1/                    # template1
│   │   ├── 13395/                # template0
│   │   └── 16384/                # kong 資料庫
│   ├── global/                   # 全域系統表
│   ├── pg_wal/                   # WAL 日誌文件
│   │   ├── 000000010000000000000001
│   │   └── archive_status/
│   ├── pg_replslot/              # 複製插槽
│   ├── log/                      # PostgreSQL 日誌
│   ├── postgresql.conf           # 主要配置文件
│   ├── pg_hba.conf              # 認證配置
│   └── postmaster.pid           # 進程 ID 文件
├── slave/                        # 從資料庫數據目錄
│   ├── base/                     # 複製的資料庫文件
│   ├── global/
│   ├── pg_wal/
│   ├── recovery.signal           # 恢復模式標識
│   ├── standby.signal            # 備用模式標識
│   ├── postgresql.conf
│   ├── pg_hba.conf
│   └── log/
├── backups/                      # 備份存儲目錄
│   ├── daily/                    # 每日完整備份
│   │   ├── kong_backup_20250917_020000.dump.gz
│   │   └── kong_backup_20250916_020000.dump.gz
│   ├── hourly/                   # 每小時增量備份
│   │   ├── kong_incr_20250917_140000.dump
│   │   └── kong_incr_20250917_130000.dump
│   ├── wal_archive/              # WAL 歸檔
│   │   ├── 000000010000000000000001
│   │   └── 000000010000000000000002
│   └── scripts/                  # 備份腳本
│       ├── full_backup.sh
│       ├── incremental_backup.sh
│       └── cleanup_old_backups.sh
└── config/                       # 資料庫配置文件
    ├── master.conf               # 主庫特定配置
    └── slave.conf                # 從庫特定配置
```

### ELK 數據存儲 (ELK Data Storage)
```bash
/srv/apim/elk/
├── elasticsearch/                # Elasticsearch 數據
│   ├── data/                     # 索引數據
│   │   ├── nodes/
│   │   └── indices/
│   └── logs/                     # ES 日誌
├── logstash/                     # Logstash 數據
│   ├── data/                     # Pipeline 數據
│   └── logs/                     # Logstash 日誌
└── kibana/                       # Kibana 數據
    ├── data/                     # 儀表板配置
    └── logs/                     # Kibana 日誌
```

### 存儲權限設置 (Storage Permission Setup)
```bash
# 創建存儲目錄
sudo mkdir -p /srv/apim/{database,elk}
sudo mkdir -p /srv/apim/database/{master,slave,backups,config}
sudo mkdir -p /srv/apim/elk/{elasticsearch,logstash,kibana}/{data,logs}

# 設置 PostgreSQL 權限 (PostgreSQL 容器使用 UID 999)
sudo chown -R 999:999 /srv/apim/database
sudo chmod -R 750 /srv/apim/database

# 設置 ELK 權限 (Elasticsearch 容器使用 UID 1000)
sudo chown -R 1000:1000 /srv/apim/elk/elasticsearch
sudo chown -R 1000:1000 /srv/apim/elk/logstash
sudo chown -R 1000:1000 /srv/apim/elk/kibana
sudo chmod -R 755 /srv/apim/elk
```

### 磁碟空間監控 (Disk Space Monitoring)
```bash
# 磁碟使用率檢查腳本
#!/bin/bash
# /srv/apim/scripts/monitoring/disk_usage_check.sh

DATABASE_PATH="/srv/apim/database"
ELK_PATH="/srv/apim/elk"
WARNING_THRESHOLD=80
CRITICAL_THRESHOLD=90

# 檢查資料庫存儲使用率
DB_USAGE=$(df -h $DATABASE_PATH | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $DB_USAGE -gt $CRITICAL_THRESHOLD ]; then
    echo "CRITICAL: Database storage usage at ${DB_USAGE}%"
elif [ $DB_USAGE -gt $WARNING_THRESHOLD ]; then
    echo "WARNING: Database storage usage at ${DB_USAGE}%"
fi

# 檢查 ELK 存儲使用率
ELK_USAGE=$(df -h $ELK_PATH | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $ELK_USAGE -gt $CRITICAL_THRESHOLD ]; then
    echo "CRITICAL: ELK storage usage at ${ELK_USAGE}%"
elif [ $ELK_USAGE -gt $WARNING_THRESHOLD ]; then
    echo "WARNING: ELK storage usage at ${ELK_USAGE}%"
fi
```

## 環境分離 (Environment Separation)

### 開發環境 (Development)
- 配置檔案: `config/env/.env.dev`
- Docker 編排: `deployments/docker/docker-compose.dev.yml`
- 存儲路徑: `/srv/apim/dev/`

### 測試環境 (Testing)
- 配置檔案: `config/env/.env.test`
- Docker 編排: `deployments/docker/docker-compose.test.yml`
- 存儲路徑: `/srv/apim/test/`

### 生產環境 (Production)
- 配置檔案: `config/env/.env.prod`
- Docker 編排: `deployments/docker/docker-compose.prod.yml`
- 存儲路徑: `/srv/apim/database/` (主要生產存儲)