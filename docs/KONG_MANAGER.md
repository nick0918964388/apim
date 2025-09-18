# Kong 管理指南

## 概述

本文檔提供Kong Gateway的完整管理指南，包括Kong Manager的限制說明以及推薦的管理方式。

## Kong版本說明

目前平台使用的Kong版本：
- **Kong**: 3.3.1 (OSS開源版本)
- **nginx**: 1021004
- **Lua**: LuaJIT 2.1.0

⚠️ **重要注意事項**: Kong Manager和Konga等圖形化界面在某些環境下可能遇到相容性問題，因此我們推薦使用以下更可靠的管理方式。

## 推薦管理方案

### 1. Kong Admin API (推薦)

Kong Admin API提供完整的RESTful API來管理所有Kong功能：

```bash
# 基礎URL
http://localhost:8001

# 查看Kong狀態
curl http://localhost:8001/status

# 查看所有服務
curl http://localhost:8001/services

# 查看所有路由
curl http://localhost:8001/routes

# 查看所有消費者
curl http://localhost:8001/consumers

# 查看插件
curl http://localhost:8001/plugins
```

### 2. 項目內建管理工具 (推薦)

平台已內建專用的管理工具，提供便捷的Kong管理功能：

#### JWT憑證管理工具
```bash
# 查看所有環境的JWT憑證
node scripts/kong_jwt_manager.js list

# 為開發環境生成Token (1小時有效)
node scripts/kong_jwt_manager.js generate maximo-hldev-api

# 生成永不過期的Token
node scripts/kong_jwt_manager.js generate maximo-hldev-api --never-expire

# 自定義過期時間 (秒)
node scripts/kong_jwt_manager.js generate maximo-hldev-api 7200
```

#### 部署驗證工具
```bash
# 全面驗證部署狀態
./scripts/validate-deployment.sh

# 檢查服務健康狀態
./scripts/validate-config.sh
```

### 3. Kong CLI命令

使用Kong命令行工具進行管理：

```bash
# 進入Kong容器
docker exec -it kong bash

# Kong配置檢查
kong config

# 檢查配置文件
kong check /etc/kong/kong.conf

# 重載配置
kong reload
```

### 4. 監控和日誌分析 (推薦)

平台提供完整的監控和日誌分析功能：

#### Kibana日誌分析
- **訪問地址**: http://localhost:5601
- **功能**: API請求日誌分析、錯誤追蹤、效能監控
- **日誌位置**: `/srv/apim/logs/maximo-api.log`

#### ELK Stack監控
```bash
# Elasticsearch健康檢查
curl http://localhost:9200/_cluster/health

# Kibana狀態檢查
curl http://localhost:5601/api/status

# Logstash狀態檢查
curl http://localhost:8080
```

### 5. 資料庫管理

```bash
# 查看PostgreSQL主從複製狀態
docker exec kong-database-master psql -U kong -d kong -c "SELECT * FROM pg_stat_replication;"

# 檢查複製延遲
docker exec kong-database-slave psql -U kong -d kong -c "SELECT NOW() - pg_last_xact_replay_timestamp() AS replication_lag;"

# 手動備份
./scripts/backup/full_backup.sh
./scripts/backup/incremental_backup.sh
```

## Kong Enterprise功能對比

| 功能 | Kong OSS | Kong Enterprise |
|------|----------|----------------|
| API Gateway核心功能 | ✅ | ✅ |
| 插件生態系統 | ✅ | ✅ + 企業插件 |
| Admin API | ✅ | ✅ |
| Kong Manager Web UI | ❌ | ✅ |
| Dev Portal | ❌ | ✅ |
| RBAC | ❌ | ✅ |
| 進階分析 | ❌ | ✅ |
| 企業支援 | ❌ | ✅ |

## 當前平台管理方式

### 完整管理流程

1. **服務和路由管理**: 使用Kong Admin API進行CRUD操作
2. **憑證和認證管理**: 使用內建的JWT管理工具
3. **即時監控**: 通過Kibana儀表板查看API使用情況
4. **系統健康檢查**: 使用自動化驗證腳本
5. **日誌分析**: ELK Stack提供完整的日誌聚合和分析
6. **備份和恢復**: 自動化的資料庫備份策略

### 日常運維任務

#### 每日檢查
```bash
# 檢查所有服務狀態
./scripts/validate-deployment.sh

# 查看API使用統計
# 訪問Kibana: http://localhost:5601
```

#### 憑證管理
```bash
# 檢查JWT憑證狀態
node scripts/kong_jwt_manager.js list

# 為新客戶端生成Token
node scripts/kong_jwt_manager.js generate client-name
```

#### 故障排除
```bash
# 查看Kong即時日誌
docker logs kong -f

# 檢查PostgreSQL複製狀態
docker exec kong-database-master psql -U kong -d kong -c "SELECT * FROM pg_stat_replication;"

# 驗證ELK Stack運行狀態
curl http://localhost:9200/_cluster/health
```

### API操作範例

#### 創建服務
```bash
curl -i -X POST http://localhost:8001/services \
  --data "name=my-service" \
  --data "url=http://example.com"
```

#### 創建路由
```bash
curl -i -X POST http://localhost:8001/services/my-service/routes \
  --data "paths[]=/my-path"
```

#### 啟用插件
```bash
curl -i -X POST http://localhost:8001/services/my-service/plugins \
  --data "name=rate-limiting" \
  --data "config.minute=100"
```

## 升級到Kong Enterprise

如需Kong Manager功能，可考慮升級到Kong Enterprise：

### 升級步驟
1. 聯繫Kong銷售團隊獲取Enterprise授權
2. 更新Docker映像檔到Enterprise版本
3. 配置Enterprise功能
4. 遷移現有配置

### Enterprise配置範例
```yaml
# docker-compose.yml
kong:
  image: kong/kong-gateway:3.3.1-alpine
  environment:
    KONG_DATABASE: postgres
    KONG_ADMIN_GUI_LISTEN: 0.0.0.0:8002
    KONG_ADMIN_GUI_URL: http://localhost:8002
    KONG_LICENSE_DATA: ${KONG_LICENSE_DATA}
```

## 總結

Kong OSS雖然沒有圖形化的Kong Manager，但本平台通過Kong Admin API、自定義管理工具和ELK Stack監控，提供了更強大且可靠的管理方案：

### ✅ 平台核心能力

- **🔧 完整的API Gateway功能**: 路由、負載均衡、速率限制、認證授權
- **🛠️ RESTful管理API**: 全功能的Kong Admin API (http://localhost:8001)
- **🔐 JWT認證管理**: 自動化的多環境憑證管理工具
- **📊 即時監控分析**: Kibana儀表板提供豐富的API使用分析
- **📝 集中式日誌**: ELK Stack處理所有API請求日誌
- **💾 自動化備份**: PostgreSQL主從複製和定時備份
- **🔍 健康檢查**: 自動化的部署驗證和服務監控
- **🏗️ 基礎設施即代碼**: Docker Compose統一管理所有服務

### 🎯 管理優勢

1. **更可靠**: Admin API直接操作，避免Web UI的相容性問題
2. **更靈活**: 可編程的管理介面，支援自動化腳本
3. **更透明**: 所有操作都有詳細的日誌記錄
4. **更快速**: 命令行操作比圖形界面更高效
5. **更安全**: 減少Web界面的安全風險

### 🚀 建議的工作流程

```bash
# 1. 每日健康檢查
./scripts/validate-deployment.sh

# 2. 管理JWT憑證
node scripts/kong_jwt_manager.js list

# 3. 監控API使用
# 瀏覽器訪問: http://localhost:5601

# 4. 配置API服務
curl -X POST http://localhost:8001/services \
  --data "name=my-service" \
  --data "url=http://backend.com"

# 5. 查看即時日誌
docker logs kong -f
```

---

**文檔版本**: 1.0
**更新日期**: 2025-09-18
**維護人員**: Kong APIM Team