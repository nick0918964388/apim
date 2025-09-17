# Kong APIM Platform

Kong API 閘道管理平台，包含高可用性 PostgreSQL 資料庫集群、ELK 監控堆疊與自動備份機制。

## 📋 專案描述

本專案提供完整的 API 管理解決方案，整合以下核心組件：

- **Kong Gateway 3.4**: API 閘道與路由管理
- **PostgreSQL 13 HA 集群**: 主從架構的高可用性資料庫
- **ELK Stack 8.11**: 即時監控與日誌分析 (Elasticsearch + Logstash + Kibana)
- **自動備份系統**: 完整備份 + 增量備份 + 備份驗證

## 🚀 快速開始

### 系統需求

- Docker >= 20.10
- Docker Compose >= 2.0
- 最低記憶體: 8GB RAM
- 最低儲存: 50GB 可用空間

### 安裝步驟

1. **克隆專案**
```bash
git clone <repository-url>
cd kong-apim
```

2. **建立存儲目錄**
```bash
sudo mkdir -p /srv/apim/database/{master,slave,backups/{daily,hourly,wal_archive}}
sudo chown -R 999:999 /srv/apim/database
```

3. **配置環境變數**
```bash
cp config/env/.env.dev config/env/.env.local
# ⚠️ CRITICAL: 修改所有預設密碼和生產配置
# 🔒 生產環境必須：
#    - 更換所有預設密碼為強密碼
#    - 啟用 SSL/TLS 加密
#    - 檢查安全設定
```

4. **啟動服務**
```bash
cd deployments/docker
docker compose --env-file ../../config/env/.env.dev up -d
```

5. **驗證部署**
```bash
./scripts/validate-deployment.sh
```

## 🔧 配置說明

### Kong Gateway
- **Proxy API**: http://localhost:8000
- **Admin API**: http://localhost:8001
- **配置文件**: `config/kong/kong.conf`

### PostgreSQL 高可用性集群
- **Master DB**: localhost:5432 (讀寫)
- **Slave DB**: localhost:5433 (只讀)
- **配置目錄**: `config/postgresql/`

### ELK 監控堆疊
- **Elasticsearch**: http://localhost:9200
- **Kibana 儀表板**: http://localhost:5601
- **Logstash**: localhost:8080 (HTTP input)

## 📊 監控儀表板

訪問 Kibana 儀表板查看：
- API 請求總覽與趨勢
- 響應時間分析 (P50/P95/P99)
- 錯誤率統計
- PostgreSQL 主從複製狀態
- 服務健康監控

## 🔄 備份與恢復

### 自動備份
- **完整備份**: 每日 02:00 執行
- **增量備份**: 每小時執行
- **備份保留**: 完整備份 30 天，增量備份 7 天

### 手動備份
```bash
# 執行完整備份
./scripts/backup/full_backup.sh

# 執行增量備份
./scripts/backup/incremental_backup.sh

# 驗證備份完整性
./scripts/backup/verify_backup.sh
```

### 恢復程序
```bash
# 恢復到新資料庫
docker exec kong-database-master pg_restore -U kong -d kong_restore -C /path/to/backup.sql.gz
```

## 🚨 故障排除

### Kong Gateway 無法啟動
1. 檢查 PostgreSQL 連接狀態
2. 確認資料庫遷移已執行
3. 查看 Kong 容器日誌

### PostgreSQL 主從複製問題
1. 檢查複製用戶權限
2. 驗證網路連接
3. 查看複製延遲狀態

### ELK Stack 啟動失敗
1. 確認記憶體配置足夠
2. 檢查 Elasticsearch 磁碟空間
3. 驗證配置文件語法

## 📁 目錄結構

```
kong-apim/
├── config/                    # 配置文件
│   ├── kong/                  # Kong 配置
│   ├── postgresql/            # PostgreSQL 配置
│   └── env/                   # 環境變數
├── deployments/
│   ├── docker/                # Docker Compose 文件
│   └── monitoring/            # ELK 配置
├── scripts/
│   ├── backup/                # 備份腳本
│   ├── postgresql/            # 資料庫腳本
│   └── validate-deployment.sh # 驗證腳本
└── docs/                      # 文檔
```

## 🔐 安全性

- 所有密碼透過環境變數配置
- PostgreSQL 複製使用專用用戶
- Kong Admin API 僅限內部網路存取
- ELK 堆疊安全性在生產環境中需要啟用

## 📈 效能監控

### 關鍵指標
- API 響應時間 < 100ms (P95)
- 服務可用性 > 99.9%
- PostgreSQL 複製延遲 < 5s
- 備份成功率 = 100%

### 告警設定
- 響應時間超過 500ms
- 錯誤率超過 5%
- 複製延遲超過 10s
- 備份失敗

## 🛠️ 開發指南

### 本地開發
```bash
# 啟動開發環境
cd deployments/docker
docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# 查看日誌
docker compose logs -f kong
```

### 配置修改
1. 修改對應配置文件
2. 重啟相關服務
3. 驗證配置生效

## 📞 支援

如需協助，請聯繫系統管理員或查看：
- [Kong 官方文檔](https://docs.konghq.com/)
- [PostgreSQL 文檔](https://www.postgresql.org/docs/)
- [ELK Stack 文檔](https://www.elastic.co/guide/)

## 📄 授權

本專案使用內部授權協議。