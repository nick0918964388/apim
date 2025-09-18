# Kibana 儀表板訪問指南

## 訪問地址
- **Kibana Web UI**: http://localhost:5601

## 已創建的資源

### 1. 數據視圖 (Data View)
- **名稱**: Kong API Logs
- **索引模式**: `kong-logs-*`
- **時間字段**: `@timestamp`
- **ID**: `ca3fcc2f-80a2-44b1-95bf-e675d79cf4ca`

### 2. 可用的關鍵字段
- `http_status` - HTTP狀態碼
- `service_name` - 服務名稱
- `route_name` - 路由名稱
- `total_latency` - 總響應時間(ms)
- `kong_latency` - Kong處理時間(ms)
- `response_category` - 響應分類 (success/client_error/server_error)
- `sla_met` - SLA達成狀態
- `performance_score` - 效能分數(0-100)
- `client_address` - 客戶端IP地址

## 建議的手動創建視覺化

### 1. API請求趨勢圖
- **類型**: Line Chart
- **X軸**: @timestamp (日期直方圖)
- **Y軸**: 請求計數
- **時間範圍**: 最近24小時

### 2. HTTP狀態碼分布
- **類型**: Pie Chart
- **分組**: http_status
- **指標**: 請求計數

### 3. 響應時間分析
- **類型**: Line Chart
- **X軸**: @timestamp
- **Y軸**: total_latency (平均值、P95)

### 4. 服務請求分布
- **類型**: Horizontal Bar Chart
- **分組**: service_name
- **指標**: 請求計數

### 5. SLA監控
- **類型**: Metric
- **指標**: sla_met (百分比)

### 6. 效能分數趨勢
- **類型**: Line Chart
- **X軸**: @timestamp
- **Y軸**: performance_score (平均值)

## 快速查詢範例

### 查看最近錯誤
```
http_status >= 400
```

### 查看慢請求
```
total_latency > 1000
```

### 查看特定服務
```
service_name: "maximo-workorders"
```

### SLA未達成的請求
```
sla_met: false
```

## 告警條件建議

1. **錯誤率告警**: 5分鐘內4xx/5xx錯誤率 > 5%
2. **響應時間告警**: 5分鐘內P95響應時間 > 2000ms
3. **SLA告警**: 5分鐘內SLA達成率 < 95%
4. **服務可用性**: 5分鐘內無請求