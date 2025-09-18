# Kong API 使用者行為分析儀表板

## 儀表板概述
專門用於分析API使用者的行為模式，包括地理分布、設備分析、使用習慣和異常檢測。

## 關鍵使用者指標

### 1. 客戶端識別指標
- **客戶端IP**: `client_address`
- **地理位置**: `geoip.*` (國家、城市、時區)
- **用戶代理**: `user_agent`
- **設備類型**: `user_agent_parsed.*`

### 2. 行為模式指標
- **請求頻率**: 每小時/每天請求數
- **活躍時段**: 使用時間分布
- **API偏好**: 最常用的服務和路由
- **會話長度**: 連續請求的時間跨度

### 3. 異常行為指標
- **高頻請求**: 短時間內大量請求
- **錯誤模式**: 連續失敗請求
- **可疑活動**: 異常地理位置、設備變更

## 視覺化組件配置

### 1. 地理分布地圖
```yaml
類型: Maps
配置:
  圖層:
    - 世界地圖
    - 點聚合圖層
  數據源: client_address
  指標: 請求計數
  顏色: 按請求數量分級
  座標字段: geoip.location
```

### 2. 用戶代理分析
```yaml
類型: Pie Chart
配置:
  主分組: user_agent_parsed.name (瀏覽器)
  子分組: user_agent_parsed.os (操作系統)
  指標: 唯一用戶數 (client_address cardinality)
```

### 3. 活躍時段熱圖
```yaml
類型: Heat Map
配置:
  X軸: @timestamp (小時)
  Y軸: @timestamp (星期)
  顏色: 請求計數
  時間範圍: 最近30天
```

### 4. 客戶端活躍度排名
```yaml
類型: Data Table
配置:
  欄位:
    - client_address
    - 請求總數
    - 最後活躍時間
    - 主要使用服務
    - 錯誤率
  排序: 請求總數 降序
  筆數: 20
```

### 5. API使用偏好分析
```yaml
類型: Sankey Diagram / Tree Map
配置:
  路徑: client_address → service_name → route_name
  指標: 請求計數
  顯示: 用戶到服務的流向
```

### 6. 會話長度分布
```yaml
類型: Histogram
配置:
  X軸: 會話時長 (分鐘)
  Y軸: 會話數量
  區間: 5分鐘間隔
  計算: 同一IP連續請求的時間跨度
```

### 7. 異常行為檢測
```yaml
類型: Metric + Line Chart
配置:
  指標:
    - 高頻用戶數 (>100請求/小時)
    - 異常地理位置數
    - 可疑用戶代理數
  趨勢: 異常行為時間序列
```

### 8. 用戶忠誠度分析
```yaml
類型: Bar Chart
配置:
  X軸: 使用天數分組 (1天, 2-7天, 8-30天, 30天+)
  Y軸: 用戶數量
  分組: 新用戶 vs 回頭用戶
```

## 進階查詢範例

### 活躍用戶分析
```kuery
# 最近24小時活躍用戶
@timestamp >= now-24h
| stats count() by client_address
| where count > 10
```

### 地理異常檢測
```kuery
# 同一用戶來自多個國家
client_address: "specific_ip" AND geoip.country_name: *
```

### 高頻請求檢測
```kuery
# 1小時內超過100次請求的IP
@timestamp >= now-1h
| stats count() by client_address
| where count > 100
```

### 設備變更檢測
```kuery
# 同一IP使用多種設備
client_address: "specific_ip"
| stats count(distinct user_agent_parsed.device) by client_address
| where count > 3
```

### 錯誤模式分析
```kuery
# 連續錯誤請求的用戶
http_status >= 400
| stats count() by client_address
| where count > 10
```

## 自動聚合查詢

### 1. 用戶行為概要統計
```json
{
  "aggs": {
    "user_summary": {
      "terms": {
        "field": "client_address",
        "size": 1000
      },
      "aggs": {
        "request_count": {
          "value_count": {
            "field": "@timestamp"
          }
        },
        "first_seen": {
          "min": {
            "field": "@timestamp"
          }
        },
        "last_seen": {
          "max": {
            "field": "@timestamp"
          }
        },
        "session_duration": {
          "bucket_script": {
            "buckets_path": {
              "first": "first_seen",
              "last": "last_seen"
            },
            "script": "params.last - params.first"
          }
        },
        "unique_services": {
          "cardinality": {
            "field": "service_name"
          }
        },
        "error_rate": {
          "bucket_script": {
            "buckets_path": {
              "errors": "errors",
              "total": "request_count"
            },
            "script": "params.errors / params.total * 100"
          }
        },
        "errors": {
          "filter": {
            "range": {
              "http_status": {
                "gte": 400
              }
            }
          }
        }
      }
    }
  }
}
```

### 2. 時間使用模式分析
```json
{
  "aggs": {
    "hourly_pattern": {
      "date_histogram": {
        "field": "@timestamp",
        "calendar_interval": "hour"
      },
      "aggs": {
        "unique_users": {
          "cardinality": {
            "field": "client_address"
          }
        },
        "avg_requests_per_user": {
          "bucket_script": {
            "buckets_path": {
              "total_requests": "_count",
              "unique_users": "unique_users"
            },
            "script": "params.total_requests / params.unique_users"
          }
        }
      }
    }
  }
}
```

### 3. 地理分布分析
```json
{
  "aggs": {
    "geographic_distribution": {
      "terms": {
        "field": "geoip.country_name",
        "size": 20
      },
      "aggs": {
        "cities": {
          "terms": {
            "field": "geoip.city_name",
            "size": 10
          }
        },
        "unique_users": {
          "cardinality": {
            "field": "client_address"
          }
        }
      }
    }
  }
}
```

## 行為分析洞察

### 1. 用戶分類
- **重度用戶**: >1000請求/天
- **中度用戶**: 100-1000請求/天
- **輕度用戶**: 10-100請求/天
- **偶爾用戶**: <10請求/天

### 2. 會話模式
- **短會話**: <5分鐘
- **中會話**: 5-30分鐘
- **長會話**: 30分鐘-2小時
- **超長會話**: >2小時

### 3. 異常行為標準
- **高頻異常**: >500請求/小時
- **地理異常**: 24小時內跨越3個以上國家
- **設備異常**: 同IP使用5種以上不同設備
- **錯誤異常**: 錯誤率>50%

## 告警配置建議

### 1. 濫用檢測告警
```yaml
條件:
  - 單IP 1小時內 >1000請求
  - 或錯誤率 >80%
嚴重性: 嚴重
動作: 立即通知 + 自動封鎖
```

### 2. 異常行為告警
```yaml
條件:
  - 地理位置異常跳躍
  - 設備類型快速變更
嚴重性: 警告
動作: 發送通知
```

### 3. 用戶活躍度告警
```yaml
條件: 活躍用戶數下降 >30%
嚴重性: 警告
動作: 發送通知
```

## 隱私保護考慮

### 1. 數據脫敏
- IP地址可選擇性脫敏
- 只保留前3個八位元組
- 定期清理歷史數據

### 2. 合規要求
- 遵循GDPR/CCPA等隱私法規
- 提供用戶數據刪除功能
- 匿名化分析選項

### 3. 安全訪問
- 限制儀表板訪問權限
- 審計日誌記錄
- 定期安全審查

## 業務價值分析

### 1. 用戶體驗優化
- 識別高價值用戶
- 優化熱門功能
- 改善用戶流程

### 2. 產品決策支持
- 功能使用統計
- 用戶需求分析
- 市場趨勢洞察

### 3. 安全風險管控
- 早期威脅檢測
- 異常行為阻斷
- 合規性監控