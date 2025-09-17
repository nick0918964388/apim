# 後端架構 (Backend Architecture)

## 系統架構概覽 (System Architecture Overview)

```
[Client] → [Kong Gateway] → [Backend Services]
    ↓          ↓
[PostgreSQL Master] ← [Kong Admin API]
    ↓ (Replication)
[PostgreSQL Slave] ← [Read Replicas]
    ↓          ↓
[ELK Stack] ← [Kong Logging] → [Kibana Dashboard]
    ↓                              ↓
[Elasticsearch] ← [Logstash] → [Real-time Monitoring]
    ↓
[/srv/apim/database] ← [Backup Storage]
```

### 監控數據流 (Monitoring Data Flow)
1. **API 請求**: Client → Kong Gateway → Backend Services
2. **日誌收集**: Kong → HTTP Log Plugin → Logstash
3. **數據處理**: Logstash → 數據轉換與豐富化 → Elasticsearch
4. **即時儀表板**: Elasticsearch → Kibana → 監控儀表板
5. **告警系統**: Kibana → 閾值監控 → 告警通知

## Kong 閘道架構 (Kong Gateway Architecture)

### 核心組件 (Core Components)

#### 1. Kong Gateway
- **角色**: API 閘道與代理服務
- **埠號配置**:
  - `8000`: Proxy 埠 (HTTP)
  - `8443`: Proxy 埠 (HTTPS)
  - `8001`: Admin API 埠
  - `8444`: Admin API 埠 (HTTPS)
- **功能**:
  - 請求路由與負載平衡
  - 認證與授權
  - 流量控制與監控
  - 插件擴展

#### 2. PostgreSQL 高可用性資料庫集群
- **架構**: 主從複製 (Master-Slave Replication)
- **主資料庫 (Master)**:
  - 埠號: `5432`
  - 功能: 讀寫操作、配置管理
  - 存儲路徑: `/srv/apim/database/master`
- **從資料庫 (Slave)**:
  - 埠號: `5433`
  - 功能: 只讀操作、讀取負載分散
  - 存儲路徑: `/srv/apim/database/slave`
- **資料內容**:
  - 服務定義 (Services)
  - 路由配置 (Routes)
  - 消費者資訊 (Consumers)
  - 插件配置 (Plugins)
- **備份存儲**: `/srv/apim/database/backups`

### 部署架構 (Deployment Architecture)

#### Docker 容器化部署 - PostgreSQL 主從架構
```yaml
services:
  # PostgreSQL 主資料庫
  kong-database-master:
    image: postgres:13
    environment:
      POSTGRES_DB: kong
      POSTGRES_USER: kong
      POSTGRES_PASSWORD: kong
      POSTGRES_REPLICATION_USER: replicator
      POSTGRES_REPLICATION_PASSWORD: replicator_password
      # 主庫配置
      PGUSER: kong
      POSTGRES_INITDB_ARGS: "--auth-host=md5"
    volumes:
      - /srv/apim/database/master:/var/lib/postgresql/data
      - ./config/postgresql/master:/etc/postgresql/conf.d
      - ./scripts/postgresql:/docker-entrypoint-initdb.d
    ports:
      - "5432:5432"
    networks:
      - kong-net
    command: >
      bash -c "
        echo 'wal_level = replica' >> /var/lib/postgresql/data/postgresql.conf &&
        echo 'max_wal_senders = 3' >> /var/lib/postgresql/data/postgresql.conf &&
        echo 'wal_keep_size = 64' >> /var/lib/postgresql/data/postgresql.conf &&
        echo 'host replication replicator 0.0.0.0/0 md5' >> /var/lib/postgresql/data/pg_hba.conf &&
        postgres
      "

  # PostgreSQL 從資料庫
  kong-database-slave:
    image: postgres:13
    environment:
      POSTGRES_USER: kong
      POSTGRES_PASSWORD: kong
      PGPASSWORD: replicator_password
    volumes:
      - /srv/apim/database/slave:/var/lib/postgresql/data
      - ./config/postgresql/slave:/etc/postgresql/conf.d
    ports:
      - "5433:5432"
    networks:
      - kong-net
    depends_on:
      - kong-database-master
    command: >
      bash -c "
        until pg_isready -h kong-database-master -p 5432; do sleep 1; done &&
        pg_basebackup -h kong-database-master -D /var/lib/postgresql/data -U replicator -W -v -P &&
        echo 'standby_mode = on' >> /var/lib/postgresql/data/postgresql.conf &&
        echo 'primary_conninfo = \"host=kong-database-master port=5432 user=replicator\"' >> /var/lib/postgresql/data/postgresql.conf &&
        postgres
      "

  # Kong Gateway
  kong:
    image: kong:latest
    depends_on:
      - kong-database-master
      - kong-database-slave
    environment:
      KONG_DATABASE: postgres
      KONG_PG_HOST: kong-database-master
      KONG_PG_PORT: 5432
      KONG_PG_USER: kong
      KONG_PG_PASSWORD: kong
      KONG_PG_DATABASE: kong
      # 只讀副本配置 (可選)
      KONG_PG_RO_HOST: kong-database-slave
      KONG_PG_RO_PORT: 5432
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
      KONG_ADMIN_LISTEN: 0.0.0.0:8001
    ports:
      - "8000:8000"
      - "8443:8443"
      - "8001:8001"
      - "8444:8444"
    networks:
      - kong-net

  # 資料庫備份服務
  kong-database-backup:
    image: postgres:13
    environment:
      PGPASSWORD: kong
    volumes:
      - /srv/apim/database/backups:/backups
      - ./scripts/backup:/backup-scripts
    networks:
      - kong-net
    depends_on:
      - kong-database-master
    command: >
      bash -c "
        while true; do
          sleep 3600;
          pg_dump -h kong-database-master -U kong -d kong > /backups/kong_backup_$(date +%Y%m%d_%H%M%S).sql;
          find /backups -name 'kong_backup_*.sql' -mtime +7 -delete;
        done
      "
```

## API 管理架構 (API Management Architecture)

### 服務註冊模式 (Service Registration Pattern)

#### 1. 服務定義結構
```yaml
# 標準服務定義
name: "{domain}-{service}-{version}"
protocol: http|https
host: backend-service-host
port: service-port
path: /service-base-path
connect_timeout: 60000
write_timeout: 60000
read_timeout: 60000
```

#### 2. 路由配置結構
```yaml
# 標準路由定義
name: "{service-name}-{method}-{endpoint}"
service: service-reference
protocols: [http, https]
methods: [GET, POST, PUT, DELETE]
paths: ["/api/v1/endpoint"]
strip_path: true
preserve_host: false
```

### 插件架構 (Plugin Architecture)

#### 認證插件 (Authentication Plugins)
1. **JWT Plugin**: Token 驗證
   ```yaml
   name: jwt
   config:
     uri_param_names: [jwt]
     cookie_names: [jwt]
     header_names: [authorization]
     claims_to_verify: [exp]
   ```

2. **OAuth 2.0 Plugin**: 授權框架
   ```yaml
   name: oauth2
   config:
     scopes: [read, write]
     mandatory_scope: true
     enable_authorization_code: true
   ```

#### 安全插件 (Security Plugins)
1. **Rate Limiting Plugin**: 流量控制
   ```yaml
   name: rate-limiting
   config:
     minute: 100
     hour: 1000
     policy: local
   ```

2. **CORS Plugin**: 跨域存取控制
   ```yaml
   name: cors
   config:
     origins: ["*"]
     methods: [GET, POST, PUT, DELETE]
     headers: [Accept, Authorization, Content-Type]
   ```

## 監控與日誌架構 (Monitoring & Logging Architecture)

### ELK Stack 完整整合

#### 1. Elasticsearch 集群配置
```yaml
# Elasticsearch 配置
elasticsearch:
  image: docker.elastic.co/elasticsearch/elasticsearch:8.11.0
  environment:
    - discovery.type=single-node
    - xpack.security.enabled=false
    - "ES_JAVA_OPTS=-Xms512m -Xmx512m"
  ports:
    - "9200:9200"
    - "9300:9300"
  volumes:
    - elasticsearch-data:/usr/share/elasticsearch/data
```

#### 2. Logstash 數據處理配置
```yaml
# Kong 日誌收集與處理配置
input {
  http {
    port => 8080
    codec => json
  }
}

filter {
  # 解析 Kong 日誌數據
  if [request] {
    mutate {
      add_field => { "service_name" => "%{[service][name]}" }
      add_field => { "route_name" => "%{[route][name]}" }
      add_field => { "consumer_id" => "%{[consumer][id]}" }
    }
  }
  
  # 計算響應時間
  if [latencies] {
    mutate {
      add_field => { "total_latency" => "%{[latencies][proxy]}" }
      add_field => { "upstream_latency" => "%{[latencies][upstream]}" }
    }
  }
  
  # 解析時間戳
  date {
    match => [ "started_at", "UNIX_MS" ]
    target => "@timestamp"
  }
  
  # 添加狀態分類
  if [response][status] >= 400 {
    mutate { add_tag => [ "error" ] }
  }
  if [response][status] >= 500 {
    mutate { add_tag => [ "server_error" ] }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "kong-api-logs-%{+YYYY.MM.dd}"
    template_name => "kong-api-template"
  }
}
```

#### 3. Kibana 儀表板配置
```yaml
# Kibana 可視化平台
kibana:
  image: docker.elastic.co/kibana/kibana:8.11.0
  environment:
    - ELASTICSEARCH_HOSTS=http://elasticsearch:9200
    - xpack.security.enabled=false
  ports:
    - "5601:5601"
  depends_on:
    - elasticsearch
```

#### 4. Kong HTTP Log Plugin 配置
```yaml
name: http-log
config:
  http_endpoint: http://logstash:8080
  method: POST
  timeout: 1000
  keepalive: 1000
  flush_timeout: 2
  queue_size: 1000
```

### 即時監控儀表板 (Real-time Monitoring Dashboard)

#### API 執行狀態監控
**Kibana 儀表板組件**:

1. **API 請求總覽 (API Request Overview)**
   - 總請求數 (實時計數器)
   - 每秒請求數 (RPS) 趨勢圖
   - 成功率百分比 (實時儀表)
   - 活躍服務數量

2. **響應時間分析 (Response Time Analysis)**
   ```
   Visualization: Line Chart
   - X軸: 時間 (最近1小時/24小時)
   - Y軸: 響應時間 (ms)
   - 系列: P50, P95, P99 百分位數
   - 篩選: 按服務、路由分組
   ```

3. **錯誤率監控 (Error Rate Monitoring)**
   ```
   Visualization: Multi-series Area Chart
   - 4xx 錯誤率趨勢
   - 5xx 錯誤率趨勢
   - 錯誤狀態碼分布 (400, 401, 403, 404, 500, 502, 503)
   - 告警閾值線 (錯誤率 > 5%)
   ```

4. **服務健康狀態 (Service Health Status)**
   ```
   Visualization: Status Grid
   - 各服務當前狀態 (綠/黃/紅)
   - 上游服務可用性
   - 最近故障時間
   - 服務響應時間健康度
   ```

5. **流量分析 (Traffic Analysis)**
   ```
   Visualization: Heat Map & Bar Chart
   - 按 API 端點的請求分布
   - 地理位置流量分布
   - 用戶代理分析
   - 請求方法分布 (GET, POST, PUT, DELETE)
   ```

### 監控指標定義 (Monitoring Metrics Definition)

#### 核心 KPI 指標
```yaml
# 響應時間指標
response_time_metrics:
  - name: "api_response_time_p50"
    description: "API 響應時間 50th 百分位數"
    unit: "milliseconds"
    threshold_warning: 100
    threshold_critical: 500

  - name: "api_response_time_p95"
    description: "API 響應時間 95th 百分位數"
    unit: "milliseconds"
    threshold_warning: 200
    threshold_critical: 1000

# 錯誤率指標
error_rate_metrics:
  - name: "api_error_rate_4xx"
    description: "4xx 客戶端錯誤率"
    unit: "percentage"
    threshold_warning: 5
    threshold_critical: 10

  - name: "api_error_rate_5xx"
    description: "5xx 服務器錯誤率"
    unit: "percentage"
    threshold_warning: 1
    threshold_critical: 5

# 吞吐量指標
throughput_metrics:
  - name: "api_requests_per_second"
    description: "每秒 API 請求數"
    unit: "requests/second"
    threshold_warning: 1000
    threshold_critical: 1500
```

### 告警配置 (Alert Configuration)

#### Kibana Watcher 告警規則
```yaml
# 高錯誤率告警
error_rate_alert:
  trigger:
    schedule: { interval: "1m" }
  input:
    search:
      request:
        indices: ["kong-api-logs-*"]
        body:
          query:
            bool:
              filter:
                range:
                  "@timestamp":
                    gte: "now-5m"
          aggs:
            error_rate:
              filters:
                filters:
                  errors:
                    range:
                      "response.status": { gte: 400 }
                  total: { match_all: {} }
  condition:
    compare:
      "ctx.payload.aggregations.error_rate.buckets.errors.doc_count":
        gt: "{{ctx.payload.aggregations.error_rate.buckets.total.doc_count * 0.05}}"

# 響應時間告警
response_time_alert:
  trigger:
    schedule: { interval: "1m" }
  input:
    search:
      request:
        indices: ["kong-api-logs-*"]
        body:
          query:
            range:
              "@timestamp": { gte: "now-5m" }
          aggs:
            avg_response_time:
              avg:
                field: "latencies.proxy"
  condition:
    compare:
      "ctx.payload.aggregations.avg_response_time.value": { gt: 1000 }
```

### 健康檢查架構 (Health Check Architecture)

#### Kong 健康檢查端點
- **Kong Status**: `GET /status` (Admin API)
- **Database Check**: Kong 自動資料庫連接檢查
- **Plugin Status**: 各插件狀態監控

#### 服務健康檢查配置
```yaml
# 後端服務健康檢查
healthchecks:
  active:
    http_path: "/health"
    healthy:
      http_statuses: [200, 302]
      interval: 10
      successes: 3
    unhealthy:
      http_statuses: [429, 500, 502, 503, 504]
      interval: 10
      http_failures: 3
```

## 擴展架構 (Scaling Architecture)

### 水平擴展 (Horizontal Scaling)
- **Kong 實例**: 多個 Kong 節點負載平衡
- **資料庫**: PostgreSQL 主從架構
- **快取**: Redis 叢集支援

### 效能最佳化 (Performance Optimization)
1. **連接池配置**: 最佳化資料庫連接
2. **快取策略**: 插件配置快取
3. **負載平衡**: 後端服務負載分散

## 安全架構 (Security Architecture)

### 網路安全
- **內部網路**: Kong 與資料庫內部通信
- **防火牆**: 僅開放必要埠號
- **SSL/TLS**: 加密傳輸

### 資料安全
- **敏感資料加密**: 資料庫層級加密
- **憑證管理**: 定期輪換 API 金鑰
- **存取日誌**: 完整的存取記錄

## PostgreSQL 高可用性架構 (PostgreSQL High Availability Architecture)

### 主從複製機制 (Master-Slave Replication)

#### 複製配置 (Replication Configuration)
```bash
# 主資料庫配置 (postgresql.conf)
wal_level = replica
max_wal_senders = 3
wal_keep_size = 64MB
archive_mode = on
archive_command = 'cp %p /srv/apim/database/wal_archive/%f'

# 認證配置 (pg_hba.conf)
host replication replicator 0.0.0.0/0 md5
```

#### 故障轉移 (Failover) 策略
1. **自動檢測**: Kong 健康檢查檢測主資料庫故障
2. **手動切換**: 提升從資料庫為新主資料庫
3. **連接重定向**: 更新 Kong 配置指向新主資料庫
4. **數據同步**: 重建複製關係

### 存儲架構 (Storage Architecture)

#### 磁碟區掛載 (Volume Mounting)
```bash
/srv/apim/database/
├── master/              # 主資料庫數據目錄
│   ├── base/           # 資料庫文件
│   ├── pg_wal/         # WAL 日誌
│   └── postgresql.conf # 主資料庫配置
├── slave/              # 從資料庫數據目錄
│   ├── base/           # 複製的資料庫文件
│   ├── pg_wal/         # 從庫 WAL
│   └── postgresql.conf # 從資料庫配置
├── backups/            # 資料庫備份目錄
│   ├── daily/          # 每日完整備份
│   ├── hourly/         # 每小時增量備份
│   └── wal_archive/    # WAL 歸檔備份
└── config/             # 資料庫配置文件
    ├── master.conf     # 主庫特定配置
    └── slave.conf      # 從庫特定配置
```

#### 權限設置 (Permission Setup)
```bash
# 創建存儲目錄
sudo mkdir -p /srv/apim/database/{master,slave,backups,config}
sudo chown -R 999:999 /srv/apim/database
sudo chmod -R 750 /srv/apim/database
```

### 備份與恢復架構 (Backup & Recovery Architecture)

#### 自動備份策略 (Automated Backup Strategy)
```yaml
# 備份服務配置
backup_schedule:
  full_backup:
    frequency: "daily"
    time: "02:00"
    retention: "30 days"
    command: "pg_dump -h kong-database-master -U kong -d kong"
  
  incremental_backup:
    frequency: "hourly"
    retention: "7 days"
    command: "pg_receivewal -h kong-database-master -U replicator"
  
  wal_archive:
    retention: "14 days"
    location: "/srv/apim/database/backups/wal_archive"
```

#### 備份腳本 (Backup Scripts)
```bash
#!/bin/bash
# /backup-scripts/kong-backup.sh

BACKUP_DIR="/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
DATABASE_HOST="kong-database-master"
DATABASE_NAME="kong"
DATABASE_USER="kong"

# 完整備份
pg_dump -h $DATABASE_HOST -U $DATABASE_USER -d $DATABASE_NAME \
  --verbose --clean --create --format=custom \
  --file="$BACKUP_DIR/daily/kong_full_backup_$TIMESTAMP.dump"

# 壓縮舊備份
gzip "$BACKUP_DIR/daily/kong_full_backup_$TIMESTAMP.dump"

# 清理超過保留期的備份
find "$BACKUP_DIR/daily" -name "kong_full_backup_*.dump.gz" -mtime +30 -delete
find "$BACKUP_DIR/hourly" -name "kong_incr_backup_*.dump" -mtime +7 -delete

# 備份驗證
if [ $? -eq 0 ]; then
    echo "$(date): Kong database backup completed successfully" >> /var/log/kong-backup.log
else
    echo "$(date): Kong database backup failed" >> /var/log/kong-backup.log
    exit 1
fi
```

#### 恢復程序 (Recovery Procedures)
```bash
# 1. 停止所有服務
docker-compose down

# 2. 從備份恢復主資料庫
pg_restore -h kong-database-master -U kong -d kong \
  --clean --create --verbose \
  /srv/apim/database/backups/daily/kong_full_backup_latest.dump.gz

# 3. 重建從資料庫
docker-compose up kong-database-slave

# 4. 驗證數據完整性
psql -h kong-database-master -U kong -d kong -c "SELECT count(*) FROM services;"
psql -h kong-database-slave -U kong -d kong -c "SELECT count(*) FROM services;"
```

### 監控與告警 (Monitoring & Alerting)

#### 資料庫健康監控
```bash
# PostgreSQL 主從同步監控
SELECT 
    client_addr,
    state,
    sent_lsn,
    write_lsn,
    flush_lsn,
    replay_lsn,
    sync_state
FROM pg_stat_replication;

# 複製延遲監控
SELECT 
    CASE 
        WHEN pg_last_wal_receive_lsn() = pg_last_wal_replay_lsn() 
        THEN 0 
        ELSE EXTRACT(EPOCH FROM now() - pg_last_xact_replay_timestamp()) 
    END AS replica_lag_seconds;
```

#### Kibana 資料庫監控儀表板
- **複製狀態**: 主從同步延遲、複製狀態
- **連接監控**: 活躍連接數、慢查詢監控
- **存儲監控**: 磁碟使用量、WAL 檔案大小
- **備份狀態**: 備份成功率、備份大小趨勢

## 災難恢復 (Disaster Recovery)

### 備份策略
- **資料庫備份**: PostgreSQL 主從架構 + 自動備份
  - 每日完整備份保留30天
  - 每小時增量備份保留7天
  - WAL 歸檔備份保留14天
- **配置備份**: Kong 配置匯出
- **日誌備份**: ELK 資料備份

### 恢復程序
1. **系統狀態評估**: 檢查主從資料庫狀態
2. **資料庫恢復**: 從最新備份恢復數據
3. **複製重建**: 重新配置主從複製關係
4. **Kong 配置恢復**: 恢復 API 閘道配置
5. **服務功能驗證**: 端到端功能測試

### 高可用性保證 (High Availability Guarantees)
- **資料庫可用性**: 99.9% (主從自動故障轉移)
- **數據持久性**: 99.99% (多重備份策略)
- **恢復時間目標 (RTO)**: < 15分鐘
- **恢復點目標 (RPO)**: < 1小時