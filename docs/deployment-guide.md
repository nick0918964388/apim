# Kong APIM 部署指南

## 部署前準備

### 系統環境要求

#### 最低配置
- **CPU**: 4 cores
- **記憶體**: 8GB RAM
- **儲存**: 50GB 可用空間
- **網路**: 1Gbps 內部網路頻寬

#### 建議配置
- **CPU**: 8 cores
- **記憶體**: 16GB RAM
- **儲存**: 200GB SSD + 500GB HDD (備份)
- **網路**: 10Gbps 內部網路頻寬

### 軟體需求
- Docker >= 20.10
- Docker Compose >= 2.0
- Git (用於版本控制)

## 詳細部署步驟

### 1. 環境準備

#### 建立存儲目錄
```bash
# 建立主要數據目錄
sudo mkdir -p /srv/apim/database/{master,slave,backups,config}
sudo mkdir -p /srv/apim/database/backups/{daily,hourly,wal_archive}
sudo mkdir -p /srv/apim/elk/{elasticsearch,logstash,kibana}

# 設定權限 (PostgreSQL 使用 UID/GID 999)
sudo chown -R 999:999 /srv/apim/database
sudo chmod -R 755 /srv/apim/database

# 設定 ELK 目錄權限 (Elasticsearch 使用 UID/GID 1000)
sudo chown -R 1000:1000 /srv/apim/elk/elasticsearch
sudo chmod -R 755 /srv/apim/elk
```

#### 系統優化設定
```bash
# 增加記憶體映射限制 (Elasticsearch 需要)
echo 'vm.max_map_count=262144' | sudo tee -a /etc/sysctl.conf
sudo sysctl -p

# 設定檔案描述符限制
echo '* soft nofile 65536' | sudo tee -a /etc/security/limits.conf
echo '* hard nofile 65536' | sudo tee -a /etc/security/limits.conf
```

### 2. 配置文件準備

#### 環境變數配置
```bash
# 複製範例配置
cp config/env/.env.dev config/env/.env.prod

# 編輯生產環境配置
vi config/env/.env.prod
```

重要配置項目：
- 修改所有預設密碼
- 設定正確的主機名稱
- 調整記憶體配置
- 設定備份保留政策

#### SSL 證書配置 (生產環境)
```bash
# 建立 SSL 目錄
mkdir -p config/ssl

# 生成自簽證書 (開發用)
openssl req -new -x509 -nodes -out config/ssl/kong.crt -keyout config/ssl/kong.key -days 365

# 或複製現有證書
cp /path/to/your/certificate.crt config/ssl/
cp /path/to/your/private.key config/ssl/
```

### 3. 服務啟動順序

#### 第一階段：資料庫服務
```bash
cd deployments/docker

# 啟動 PostgreSQL Master
docker compose --env-file ../../config/env/.env.prod up -d kong-database-master

# 等待 Master 就緒
docker compose logs -f kong-database-master
# 等待看到 "database system is ready to accept connections"

# 啟動 PostgreSQL Slave
docker compose --env-file ../../config/env/.env.prod up -d kong-database-slave

# 驗證主從複製
docker exec kong-database-master psql -U kong -d kong -c "SELECT * FROM pg_stat_replication;"
```

#### 第二階段：ELK 監控堆疊
```bash
# 啟動 Elasticsearch
docker compose --env-file ../../config/env/.env.prod up -d elasticsearch

# 等待 Elasticsearch 就緒
curl -X GET "localhost:9200/_cluster/health?wait_for_status=yellow&timeout=60s"

# 啟動 Logstash
docker compose --env-file ../../config/env/.env.prod up -d logstash

# 啟動 Kibana
docker compose --env-file ../../config/env/.env.prod up -d kibana

# 驗證 ELK 狀態
curl -X GET "localhost:9200/_cat/health?v"
curl -X GET "localhost:5601/api/status"
```

#### 第三階段：Kong Gateway
```bash
# 執行資料庫遷移
docker compose --env-file ../../config/env/.env.prod run --rm kong-migration

# 啟動 Kong Gateway
docker compose --env-file ../../config/env/.env.prod up -d kong

# 驗證 Kong 狀態
curl -X GET "localhost:8001/status"
```

#### 第四階段：備份服務
```bash
# 啟動備份服務
docker compose --env-file ../../config/env/.env.prod up -d kong-backup

# 手動測試備份
docker exec kong-backup /scripts/full_backup.sh
```

### 4. 初始化配置

#### Kong HTTP Log Plugin 配置
```bash
# 配置全域 HTTP Log Plugin
curl -X POST localhost:8001/plugins \
  --data "name=http-log" \
  --data "config.http_endpoint=http://logstash:8080" \
  --data "config.method=POST" \
  --data "config.timeout=1000" \
  --data "config.keepalive=1000"
```

#### Kibana 索引模式設定
1. 訪問 http://localhost:5601
2. 進入 Stack Management > Index Patterns
3. 建立索引模式：`kong-api-logs-*`
4. 設定時間欄位：`@timestamp`

### 5. 健康檢查

#### 服務狀態檢查
```bash
# 執行完整驗證
./scripts/validate-deployment.sh

# 個別服務檢查
docker compose ps
docker compose logs kong
docker compose logs kong-database-master
docker compose logs elasticsearch
```

#### 主從複製檢查
```bash
# 檢查複製狀態
docker exec kong-database-master psql -U kong -d kong -c "
SELECT client_addr, state, sync_state 
FROM pg_stat_replication;"

# 檢查複製延遲
docker exec kong-database-slave psql -U kong -d kong -c "
SELECT CASE 
    WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() 
    THEN 0 
    ELSE EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp()) 
END AS replica_lag_seconds;"
```

## 生產環境調優

### PostgreSQL 效能調優
```bash
# 編輯 PostgreSQL 配置
vi config/postgresql/master/postgresql.conf

# 重要參數調整：
# shared_buffers = 2GB          # 25% of RAM
# effective_cache_size = 6GB    # 75% of RAM
# work_mem = 16MB
# maintenance_work_mem = 512MB
# checkpoint_timeout = 15min
# max_wal_size = 4GB
```

### ELK Stack 調優
```bash
# Elasticsearch heap size 設定
export ES_JAVA_OPTS="-Xms2g -Xmx2g"  # 50% of available RAM

# Logstash 效能設定
vi deployments/monitoring/logstash/logstash.yml
# pipeline.workers: 4
# pipeline.batch.size: 1000
# pipeline.batch.delay: 50
```

### Kong Gateway 調優
```bash
# Kong 效能設定
vi config/kong/kong.conf

# worker_processes = auto
# worker_connections = 4096
# upstream_keepalive_pool_size = 256
# upstream_keepalive_max_requests = 10000
```

## 故障轉移程序

### PostgreSQL 主從切換
```bash
# 1. 停止主資料庫 (模擬故障)
docker stop kong-database-master

# 2. 提升從資料庫為主資料庫
docker exec kong-database-slave pg_ctl promote -D /var/lib/postgresql/data

# 3. 更新 Kong 配置指向新主資料庫
# 修改環境變數 KONG_PG_HOST=kong-database-slave
# 重啟 Kong 服務
docker restart kong

# 4. 重建新的從資料庫 (原主資料庫修復後)
# ... 詳見故障恢復文檔
```

## 監控與告警設定

### 關鍵監控指標
- Kong Gateway 可用性
- PostgreSQL 主從複製延遲
- Elasticsearch 集群健康狀態
- API 響應時間與錯誤率
- 系統資源使用率

### 告警閾值
- API P95 響應時間 > 500ms
- PostgreSQL 複製延遲 > 10s
- Elasticsearch 磁碟使用率 > 85%
- 任何服務健康檢查失敗

## 備份策略

### 自動備份排程
- **完整備份**: 每日 02:00
- **增量備份**: 每小時
- **WAL 歸檔**: 持續歸檔

### 備份驗證
- 每週執行備份恢復測試
- 定期檢查備份檔案完整性
- 監控備份儲存空間使用

### 災難恢復
- RTO (恢復時間目標): < 15 分鐘
- RPO (恢復點目標): < 1 小時
- 異地備份：建議設定遠端備份存儲

## 安全性考量

### 網路安全
- 使用防火牆限制埠號存取
- 僅內部網路存取 Admin API
- 啟用 SSL/TLS 加密

### 認證授權
- 修改所有預設密碼
- 使用強密碼策略
- 定期輪換密碼

### 稽核日誌
- 啟用所有服務的稽核日誌
- 集中日誌管理
- 定期檢查異常存取

## 維護作業

### 定期維護
- 每月檢查系統更新
- 每季度執行效能測試
- 每半年檢查儲存容量規劃

### 版本更新
- 建立測試環境驗證
- 制定回滾計畫
- 逐步更新策略 (藍綠部署)