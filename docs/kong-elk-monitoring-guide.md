# Kong API Gateway - ELK Stack 監控系統完整指南

## 概述

本文檔提供Kong API Gateway與ELK Stack (Elasticsearch, Logstash, Kibana) 整合的完整監控解決方案，實現即時API監控、使用者行為分析、效能監控和自動告警。

## 系統架構

```
Kong Gateway → Logstash → Elasticsearch → Kibana
      ↓              ↓            ↓
   HTTP-Log      數據處理     即時查詢      視覺化儀表板
   Plugin       GeoIP分析     索引存儲      效能分析
   (port 8080)  User-Agent    ILM管理      使用者行為
                延遲統計                   告警監控
```

### 核心組件

1. **Kong Gateway 3.8**: API代理和管理
2. **Elasticsearch 8.11**: 日誌存儲和搜索引擎
3. **Logstash 8.11**: 日誌處理和數據轉換
4. **Kibana 8.11**: 數據視覺化和儀表板

## 部署配置

### 1. Kong HTTP-Log 插件配置

為API路由啟用HTTP-Log插件，直接發送日誌到Logstash：

```bash
# 為特定路由配置HTTP-Log插件
curl -X POST http://localhost:8001/routes/{route-id}/plugins \
  --data "name=http-log" \
  --data "config.http_endpoint=http://logstash:8080/kong-logs" \
  --data "config.method=POST" \
  --data "config.content_type=application/json" \
  --data "config.timeout=10000" \
  --data "config.keepalive=60000"

# 全域配置 (所有路由)
curl -X POST http://localhost:8001/plugins \
  --data "name=http-log" \
  --data "config.http_endpoint=http://logstash:8080/kong-logs" \
  --data "config.method=POST" \
  --data "config.content_type=application/json"
```

### 2. Logstash Pipeline 配置

**位置**: `/home/nickyin/apim/deployments/monitoring/logstash/kong-logs.conf`

```ruby
input {
  http {
    port => 8080
    codec => "json"
  }
}

filter {
  # 安全的延遲字段提取
  if [latencies][request] and [latencies][request] != "" and [latencies][request] != "null" {
    ruby {
      code => "
        val = event.get('[latencies][request]')
        if val.is_a?(Numeric) and val >= 0
          event.set('total_latency', val.to_i)
        end
      "
    }
  }

  # GeoIP 地理位置解析
  if [client_ip] and [client_ip] != "127.0.0.1" {
    geoip {
      source => "client_ip"
      target => "geoip"
    }
  }

  # User-Agent 解析
  if [request][headers]["user-agent"] {
    useragent {
      source => "[request][headers][user-agent]"
      target => "user_agent_parsed"
    }
  }

  # 響應狀態分類
  if [response][status] {
    if [response][status] >= 200 and [response][status] < 300 {
      mutate { add_field => { "status_category" => "success" } }
    } else if [response][status] >= 300 and [response][status] < 400 {
      mutate { add_field => { "status_category" => "redirect" } }
    } else if [response][status] >= 400 and [response][status] < 500 {
      mutate { add_field => { "status_category" => "client_error" } }
    } else if [response][status] >= 500 {
      mutate { add_field => { "status_category" => "server_error" } }
    }
  }
}

output {
  elasticsearch {
    hosts => ["elasticsearch:9200"]
    index => "kong-logs-%{+YYYY.MM.dd}"
    template_name => "kong-logs"
    template => "/usr/share/logstash/kong-template.json"
    template_overwrite => true
  }
}
```

### 3. Elasticsearch 索引配置

**位置**: `/home/nickyin/apim/deployments/monitoring/elasticsearch/kong-logs-template.json`

索引模板包含：
- ILM生命周期管理策略
- 效能優化設置
- 完整字段映射 (IP地址、延遲、狀態碼等)
- 地理位置和用戶代理字段支持

## 監控儀表板

### 1. API概覽儀表板

**主要指標**:
- 總請求數與QPS
- 錯誤率分布 (2xx/3xx/4xx/5xx)
- 平均響應時間趨勢
- 熱門API端點
- 地理分布圖

**關鍵視覺化**:
```yaml
- 請求數量時間序列圖
- 錯誤率餅圖
- 響應時間直方圖
- API端點使用量表格
- 世界地圖 (按請求量上色)
```

### 2. 效能分析儀表板

**效能指標**:
- P50/P90/P95/P99 響應時間
- SLA達成率 (95% < 2秒)
- 效能得分計算
- 服務延遲分解
- 流量模式分析

**告警閾值**:
- P95 > 2000ms: 效能警告
- 錯誤率 > 10%: 嚴重告警
- SLA < 95%: 服務等級告警

### 3. 使用者行為儀表板

**行為分析**:
- 活躍用戶統計與排名
- 會話長度分布
- 地理位置分析
- 設備和瀏覽器統計
- 異常行為檢測

**使用者分類**:
- 重度用戶: >1000請求/天
- 中度用戶: 100-1000請求/天
- 輕度用戶: 10-100請求/天
- 偶爾用戶: <10請求/天

### 4. 服務監控儀表板

**服務健康度**:
- 各服務可用性百分比
- 服務間依賴關係
- 錯誤模式分析
- 容量規劃指標
- 服務等級協議 (SLA) 監控

## 自動告警系統

由於Elasticsearch Watcher需要付費授權，本系統採用腳本式告警機制。

### 告警腳本

**位置**: `/home/nickyin/apim/scripts/monitoring-alerts.sh`

**監控項目**:

1. **錯誤率監控** (每5分鐘)
   - 閾值: 10%
   - 嚴重性: 嚴重
   - 動作: 日誌記錄 + Webhook通知

2. **響應時間監控** (每5分鐘)
   - 閾值: P95 > 2000ms
   - 嚴重性: 警告
   - 動作: 效能告警

3. **高頻請求監控** (每分鐘)
   - 閾值: 500請求/5分鐘 (單IP)
   - 嚴重性: 嚴重
   - 動作: 濫用檢測告警

4. **服務可用性監控** (每2分鐘)
   - 閾值: 可用性 < 95% 或 5分鐘無活動
   - 嚴重性: 嚴重
   - 動作: 服務停機告警

### 設置告警系統

```bash
# 設置自動監控 (Cron每5分鐘執行)
/home/nickyin/apim/scripts/monitoring-alerts.sh setup

# 手動執行監控檢查
/home/nickyin/apim/scripts/monitoring-alerts.sh run

# 查看告警日誌
/home/nickyin/apim/scripts/monitoring-alerts.sh logs

# 查看系統狀態
/home/nickyin/apim/scripts/monitoring-alerts.sh status
```

## 效能監控腳本

### 1. 效能監控腳本

**位置**: `/home/nickyin/apim/scripts/performance-monitor.sh`

**功能**:
- P50/P90/P95/P99 響應時間計算
- SLA 達成率統計
- 效能得分算法
- 詳細效能報告

**使用方式**:
```bash
# 查看最近1小時效能報告
./scripts/performance-monitor.sh 1h

# 查看最近24小時效能報告
./scripts/performance-monitor.sh 24h

# 生成詳細效能分析
./scripts/performance-monitor.sh 7d --detailed
```

### 2. 使用者行為監控腳本

**位置**: `/home/nickyin/apim/scripts/user-behavior-monitor.sh`

**功能**:
- 活躍用戶分析
- 地理分布統計
- 異常行為檢測
- 用戶風險評估

**使用方式**:
```bash
# 分析最近24小時用戶行為
./scripts/user-behavior-monitor.sh 24h

# 檢測異常用戶行為
./scripts/user-behavior-monitor.sh anomaly

# 地理分布分析
./scripts/user-behavior-monitor.sh geo
```

## 維護和最佳實踐

### 1. 索引生命周期管理 (ILM)

```yaml
Policy: kong-logs-policy
階段:
  - Hot: 1天 (即時查詢)
  - Warm: 7天 (歷史分析)
  - Cold: 30天 (歸檔存儲)
  - Delete: 90天 (自動刪除)
```

### 2. 備份策略

```bash
# 每日備份 Elasticsearch 索引
0 2 * * * /home/nickyin/apim/scripts/backup-elasticsearch.sh

# 每週備份 Kibana 儀表板配置
0 3 * * 0 /home/nickyin/apim/scripts/backup-kibana-config.sh
```

### 3. 效能調優

**Elasticsearch**:
```yaml
# elasticsearch.yml 設定
indices.memory.index_buffer_size: 20%
indices.fielddata.cache.size: 30%
bootstrap.memory_lock: true
```

**Logstash**:
```yaml
# logstash.yml 設定
pipeline.workers: 4
pipeline.batch.size: 1000
pipeline.batch.delay: 50
```

### 4. 安全設定

**網絡安全**:
- 限制Elasticsearch只能從內部網絡訪問
- 使用防火牆規則保護Kibana端口
- 啟用HTTPS和身份驗證

**數據隱私**:
- IP地址脫敏處理
- 敏感請求參數過濾
- 遵循GDPR/CCPA合規要求

## 故障排除

### 常見問題

1. **Logstash無法接收Kong日誌**
   ```bash
   # 檢查Logstash HTTP輸入監聽狀態
   docker logs kong-logstash | grep "Started http input"

   # 檢查Kong插件配置
   curl http://localhost:8001/plugins | jq '.data[] | select(.name=="http-log")'
   ```

2. **Elasticsearch索引創建失败**
   ```bash
   # 檢查索引模板
   curl http://localhost:9200/_template/kong-logs?pretty

   # 檢查叢集健康狀態
   curl http://localhost:9200/_cluster/health?pretty
   ```

3. **Kibana儀表板無數據**
   ```bash
   # 檢查索引模式
   curl http://localhost:5601/api/saved_objects/_find?type=index-pattern

   # 檢查索引數據
   curl http://localhost:9200/kong-logs-*/_count
   ```

### 效能問題

1. **查詢響應慢**
   - 檢查索引分片配置
   - 優化查詢語句
   - 增加節點內存

2. **磁碟空間不足**
   - 檢查ILM策略執行
   - 手動刪除舊索引
   - 增加存儲容量

## 監控指標參考

### 關鍵KPI

| 指標 | 閾值 | 嚴重性 | 說明 |
|------|------|--------|------|
| API錯誤率 | >10% | 嚴重 | 5分鐘內錯誤請求比例 |
| P95響應時間 | >2000ms | 警告 | 95%請求響應時間 |
| 服務可用性 | <95% | 嚴重 | 成功請求比例 |
| 高頻請求 | >500/5min | 嚴重 | 單IP請求頻率 |
| 磁碟使用率 | >85% | 警告 | Elasticsearch存儲 |
| 記憶體使用率 | >90% | 警告 | JVM堆記憶體 |

### 業務指標

| 指標 | 計算方式 | 業務價值 |
|------|----------|----------|
| API採用率 | 各端點使用量 | 產品功能受歡迎程度 |
| 用戶留存率 | 回訪用戶/總用戶 | 用戶粘性和滿意度 |
| 地理覆蓋 | 不同國家/地區用戶數 | 市場滲透率 |
| 會話時長 | 用戶平均使用時間 | 用戶參與度 |

## 擴展建議

### 1. 機器學習分析

```yaml
功能: Elasticsearch ML 異常檢測
應用:
  - 自動識別異常流量模式
  - 預測API使用量趨勢
  - 智能告警閾值調整
```

### 2. 整合APM

```yaml
工具: Elastic APM
好處:
  - 應用層面效能監控
  - 分散式追蹤
  - 錯誤堆疊追蹤
```

### 3. 容器監控

```yaml
工具: Metricbeat + Elasticsearch
監控:
  - Docker容器資源使用
  - Kong進程狀態
  - 系統級別指標
```

## 結語

本監控系統提供Kong API Gateway的全面監控解決方案，涵蓋效能分析、使用者行為、安全監控和自動告警。通過ELK Stack的強大功能，實現即時監控、歷史分析和預測性維護，確保API服務的高可用性和優異效能。

如需技術支援或進一步客製化，請參考相關腳本和配置文件，或聯繫系統管理員。