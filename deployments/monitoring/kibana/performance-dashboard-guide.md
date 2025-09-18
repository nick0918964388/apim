# Kong API 效能分析儀表板配置指南

## 儀表板概述
專門用於深度分析API Gateway效能指標，包括響應時間分布、SLA監控、瓶頸識別等。

## 關鍵效能指標 (KPIs)

### 1. 響應時間百分位數
- **P50**: 50%的請求響應時間
- **P90**: 90%的請求響應時間
- **P95**: 95%的請求響應時間
- **P99**: 99%的請求響應時間

### 2. 效能分級指標
- **fast**: < 100ms
- **medium**: 100-500ms
- **slow**: 500-1000ms
- **very_slow**: > 1000ms

### 3. SLA監控指標
- **可用性SLA**: 非5xx錯誤率
- **效能SLA**: 響應時間 < 2000ms
- **綜合SLA**: 兩個條件都達成

## 視覺化組件配置

### 1. 響應時間百分位數趨勢
```yaml
類型: Line Chart
配置:
  X軸: @timestamp (時間)
  Y軸:
    - total_latency (P50百分位數)
    - total_latency (P90百分位數)
    - total_latency (P95百分位數)
    - total_latency (P99百分位數)
  時間間隔: 5分鐘
```

### 2. 效能分數儀表盤
```yaml
類型: Gauge/Metric
配置:
  指標: performance_score (平均值)
  範圍: 0-100
  閾值:
    - 綠色: 80-100 (優秀)
    - 黃色: 60-79 (良好)
    - 紅色: 0-59 (需改善)
```

### 3. 延遲分類分布
```yaml
類型: Pie Chart
配置:
  分組: latency_category.keyword
  指標: 計數
  顏色:
    - fast: 綠色
    - medium: 黃色
    - slow: 橙色
    - very_slow: 紅色
```

### 4. SLA達成率監控
```yaml
類型: Metric Grid
配置:
  指標:
    - sla_available (百分比)
    - sla_performance (百分比)
    - sla_met (百分比)
  目標: > 95%
```

### 5. Kong vs Proxy延遲對比
```yaml
類型: Line Chart
配置:
  X軸: @timestamp
  Y軸:
    - kong_latency (平均值)
    - proxy_latency (平均值，過濾 >= 0)
  說明: 識別瓶頸來源
```

### 6. 服務效能熱圖
```yaml
類型: Heat Map
配置:
  X軸: @timestamp (時間段)
  Y軸: service_name
  顏色: total_latency (平均值)
  顏色範圍: 綠色(快) → 紅色(慢)
```

### 7. 最慢請求TOP 10
```yaml
類型: Data Table
配置:
  欄位:
    - @timestamp
    - service_name
    - route_name
    - total_latency
    - http_status
    - client_address
  排序: total_latency 降序
  筆數: 10
```

### 8. 效能異常檢測
```yaml
類型: Line Chart
配置:
  X軸: @timestamp
  Y軸: total_latency (平均值)
  異常檢測: 啟用
  信賴區間: 95%
```

## 進階查詢範例

### 慢請求分析
```kuery
total_latency > 1000 AND http_status < 500
```

### 效能惡化趨勢
```kuery
performance_score < 70
```

### SLA違反事件
```kuery
sla_met: false
```

### 特定服務效能分析
```kuery
service_name: "maximo-workorders" AND latency_category: "slow"
```

### Kong處理瓶頸
```kuery
kong_latency > proxy_latency AND proxy_latency > 0
```

## 告警設定建議

### 1. 響應時間告警
```yaml
條件: P95響應時間 > 2000ms (持續5分鐘)
嚴重性: 警告
動作: 發送通知
```

### 2. 效能分數告警
```yaml
條件: 平均效能分數 < 70 (持續10分鐘)
嚴重性: 警告
動作: 發送通知
```

### 3. SLA違反告警
```yaml
條件: SLA達成率 < 95% (持續5分鐘)
嚴重性: 嚴重
動作: 立即通知
```

### 4. 異常延遲告警
```yaml
條件: P99響應時間超過基線2倍
嚴重性: 嚴重
動作: 立即通知
```

## 自動刷新設定
- **推薦間隔**: 30秒
- **時間範圍**: 最近1小時 (即時監控)
- **歷史分析**: 最近24小時或7天

## 效能基準線
基於歷史數據建立效能基準:
- **良好響應時間**: P95 < 500ms
- **可接受響應時間**: P95 < 1000ms
- **目標SLA**: 99.9%可用性, 95%效能達成
- **目標效能分數**: > 85分

## 使用場景

### 1. 日常效能監控
- 檢查SLA達成情況
- 監控響應時間趨勢
- 識別效能異常

### 2. 效能調優
- 分析瓶頸來源
- 比較不同服務效能
- 評估優化效果

### 3. 容量規劃
- 分析流量vs效能關係
- 預測效能趨勢
- 規劃資源擴展

### 4. 故障排除
- 快速定位慢請求
- 分析效能惡化原因
- 追蹤問題修復效果