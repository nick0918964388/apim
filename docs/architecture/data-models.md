# 數據模型 (Data Models)

## API 監控數據模型 (API Monitoring Data Models)

### Kong 日誌數據結構 (Kong Log Data Structure)

#### 核心日誌欄位 (Core Log Fields)
```json
{
  "@timestamp": "2025-09-17T10:30:00.000Z",
  "started_at": 1726570200000,
  "client_ip": "192.168.1.100",
  "request": {
    "method": "GET",
    "uri": "/api/v1/users/123",
    "url": "https://api.example.com/api/v1/users/123",
    "size": 256,
    "querystring": {
      "include": "profile,preferences"
    },
    "headers": {
      "user-agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
      "authorization": "Bearer jwt-token",
      "content-type": "application/json"
    }
  },
  "response": {
    "status": 200,
    "size": 1024,
    "headers": {
      "content-type": "application/json",
      "x-ratelimit-remaining": "99"
    }
  },
  "service": {
    "id": "user-service-v1-id",
    "name": "user-service-v1",
    "host": "user-backend",
    "port": 3000,
    "protocol": "http"
  },
  "route": {
    "id": "user-get-route-id", 
    "name": "user-get-route",
    "paths": ["/api/v1/users"],
    "methods": ["GET"]
  },
  "consumer": {
    "id": "consumer-123",
    "username": "api-client-app"
  },
  "latencies": {
    "proxy": 45,
    "gateway": 12,
    "request": 57
  }
}
```

### 監控指標數據模型 (Monitoring Metrics Data Model)

#### 響應時間指標 (Response Time Metrics)
```json
{
  "metric_type": "response_time",
  "timestamp": "2025-09-17T10:30:00.000Z",
  "service_name": "user-service-v1",
  "route_name": "user-get-route",
  "measurements": {
    "p50": 45,
    "p90": 78,
    "p95": 125,
    "p99": 280,
    "max": 450,
    "min": 12,
    "avg": 67,
    "count": 1500
  },
  "time_window": "1m",
  "labels": {
    "environment": "production",
    "version": "v1",
    "method": "GET"
  }
}
```

#### 錯誤率指標 (Error Rate Metrics)
```json
{
  "metric_type": "error_rate",
  "timestamp": "2025-09-17T10:30:00.000Z",
  "service_name": "user-service-v1",
  "measurements": {
    "total_requests": 1500,
    "error_4xx_count": 45,
    "error_5xx_count": 5,
    "error_4xx_rate": 3.0,
    "error_5xx_rate": 0.33,
    "total_error_rate": 3.33,
    "success_rate": 96.67
  },
  "error_breakdown": {
    "400": 5,
    "401": 15,
    "403": 10,
    "404": 15,
    "500": 2,
    "502": 1,
    "503": 2
  },
  "time_window": "1m"
}
```

#### 流量指標 (Traffic Metrics)
```json
{
  "metric_type": "traffic",
  "timestamp": "2025-09-17T10:30:00.000Z",
  "measurements": {
    "requests_per_second": 25.5,
    "bytes_in_per_second": 6400,
    "bytes_out_per_second": 25600,
    "concurrent_connections": 120
  },
  "breakdown_by_method": {
    "GET": 1200,
    "POST": 200,
    "PUT": 80,
    "DELETE": 20
  },
  "breakdown_by_service": {
    "user-service-v1": 800,
    "order-service-v1": 400,
    "payment-service-v1": 300
  }
}
```

### Elasticsearch 索引映射 (Elasticsearch Index Mapping)

#### Kong 日誌索引映射
```json
{
  "mappings": {
    "properties": {
      "@timestamp": {
        "type": "date"
      },
      "started_at": {
        "type": "date",
        "format": "epoch_millis"
      },
      "client_ip": {
        "type": "ip"
      },
      "request": {
        "properties": {
          "method": {
            "type": "keyword"
          },
          "uri": {
            "type": "keyword"
          },
          "size": {
            "type": "long"
          }
        }
      },
      "response": {
        "properties": {
          "status": {
            "type": "integer"
          },
          "size": {
            "type": "long"
          }
        }
      },
      "service": {
        "properties": {
          "name": {
            "type": "keyword"
          },
          "host": {
            "type": "keyword"
          },
          "port": {
            "type": "integer"
          }
        }
      },
      "route": {
        "properties": {
          "name": {
            "type": "keyword"
          },
          "paths": {
            "type": "keyword"
          },
          "methods": {
            "type": "keyword"
          }
        }
      },
      "latencies": {
        "properties": {
          "proxy": {
            "type": "integer"
          },
          "gateway": {
            "type": "integer"
          },
          "request": {
            "type": "integer"
          }
        }
      },
      "total_latency": {
        "type": "integer"
      },
      "upstream_latency": {
        "type": "integer"
      }
    }
  }
}
```

### Kibana 儀表板數據查詢 (Kibana Dashboard Data Queries)

#### 響應時間百分位數查詢
```json
{
  "query": {
    "bool": {
      "filter": [
        {
          "range": {
            "@timestamp": {
              "gte": "now-1h"
            }
          }
        }
      ]
    }
  },
  "aggs": {
    "response_time_percentiles": {
      "percentiles": {
        "field": "latencies.proxy",
        "percents": [50, 90, 95, 99]
      }
    },
    "response_time_over_time": {
      "date_histogram": {
        "field": "@timestamp",
        "interval": "1m"
      },
      "aggs": {
        "avg_response_time": {
          "avg": {
            "field": "latencies.proxy"
          }
        }
      }
    }
  }
}
```

#### 錯誤率統計查詢
```json
{
  "query": {
    "bool": {
      "filter": [
        {
          "range": {
            "@timestamp": {
              "gte": "now-1h"
            }
          }
        }
      ]
    }
  },
  "aggs": {
    "total_requests": {
      "value_count": {
        "field": "@timestamp"
      }
    },
    "error_4xx": {
      "filter": {
        "range": {
          "response.status": {
            "gte": 400,
            "lt": 500
          }
        }
      }
    },
    "error_5xx": {
      "filter": {
        "range": {
          "response.status": {
            "gte": 500
          }
        }
      }
    },
    "status_code_breakdown": {
      "terms": {
        "field": "response.status",
        "size": 20
      }
    }
  }
}
```

#### 服務流量分析查詢
```json
{
  "query": {
    "bool": {
      "filter": [
        {
          "range": {
            "@timestamp": {
              "gte": "now-24h"
            }
          }
        }
      ]
    }
  },
  "aggs": {
    "services": {
      "terms": {
        "field": "service.name",
        "size": 50
      },
      "aggs": {
        "request_count": {
          "value_count": {
            "field": "@timestamp"
          }
        },
        "avg_response_time": {
          "avg": {
            "field": "latencies.proxy"
          }
        },
        "error_rate": {
          "filter": {
            "range": {
              "response.status": {
                "gte": 400
              }
            }
          }
        },
        "requests_over_time": {
          "date_histogram": {
            "field": "@timestamp",
            "interval": "1h"
          }
        }
      }
    }
  }
}
```

### 告警數據模型 (Alert Data Model)

#### 告警事件結構
```json
{
  "alert_id": "error-rate-high-001",
  "alert_type": "error_rate_threshold",
  "severity": "warning",
  "timestamp": "2025-09-17T10:35:00.000Z",
  "service_name": "user-service-v1",
  "metric": {
    "name": "error_rate_5xx",
    "current_value": 7.5,
    "threshold_value": 5.0,
    "unit": "percentage"
  },
  "time_window": "5m",
  "description": "5xx error rate exceeded threshold",
  "status": "active",
  "tags": [
    "production",
    "critical-service"
  ],
  "context": {
    "total_requests": 1000,
    "error_count": 75,
    "affected_endpoints": [
      "/api/v1/users",
      "/api/v1/users/{id}"
    ]
  }
}
```

### 數據保留政策 (Data Retention Policy)

#### Elasticsearch 索引生命週期管理
```json
{
  "policy": "kong-logs-policy",
  "phases": {
    "hot": {
      "actions": {
        "rollover": {
          "max_size": "10GB",
          "max_age": "1d"
        }
      }
    },
    "warm": {
      "min_age": "7d",
      "actions": {
        "allocate": {
          "number_of_replicas": 0
        }
      }
    },
    "cold": {
      "min_age": "30d",
      "actions": {
        "allocate": {
          "number_of_replicas": 0
        }
      }
    },
    "delete": {
      "min_age": "90d"
    }
  }
}
```

### 數據聚合規則 (Data Aggregation Rules)

#### 即時聚合 (Real-time Aggregation)
- **時間窗口**: 1分鐘滾動窗口
- **聚合指標**: 平均響應時間、錯誤率、請求計數
- **更新頻率**: 每10秒更新一次

#### 歷史聚合 (Historical Aggregation)
- **小時級聚合**: 保留1週
- **日級聚合**: 保留3個月  
- **週級聚合**: 保留1年
- **月級聚合**: 保留3年