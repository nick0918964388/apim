#!/bin/bash

# Kong API Performance Monitor Script
# 用於定期檢查API Gateway效能指標

# 設定參數
ELASTICSEARCH_URL="http://localhost:9200"
INDEX_PATTERN="kong-logs-current"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 輸出函數
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} Kong API Performance Monitor${NC}"
    echo -e "${BLUE} 檢查時間: $TIMESTAMP${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

print_section() {
    echo -e "${BLUE}📊 $1${NC}"
    echo "----------------------------------------"
}

print_metric() {
    local label="$1"
    local value="$2"
    local unit="$3"
    local status="$4"

    case $status in
        "good")
            echo -e "  ${GREEN}✓${NC} $label: ${GREEN}$value$unit${NC}"
            ;;
        "warning")
            echo -e "  ${YELLOW}⚠${NC} $label: ${YELLOW}$value$unit${NC}"
            ;;
        "critical")
            echo -e "  ${RED}✗${NC} $label: ${RED}$value$unit${NC}"
            ;;
        *)
            echo -e "  ${NC}• $label: $value$unit${NC}"
            ;;
    esac
}

# 檢查Elasticsearch連線
check_elasticsearch() {
    if ! curl -s "$ELASTICSEARCH_URL/_cluster/health" > /dev/null; then
        echo -e "${RED}錯誤: 無法連接到Elasticsearch${NC}"
        exit 1
    fi
}

# 獲取響應時間百分位數
get_response_time_percentiles() {
    print_section "響應時間分析"

    local result=$(curl -s "$ELASTICSEARCH_URL/$INDEX_PATTERN/_search" -H "Content-Type: application/json" -d '{
        "size": 0,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-1h"
                }
            }
        },
        "aggs": {
            "percentiles": {
                "percentiles": {
                    "field": "total_latency",
                    "percents": [50, 90, 95, 99]
                }
            }
        }
    }')

    local p50=$(echo "$result" | jq -r '.aggregations.percentiles.values["50.0"]' 2>/dev/null)
    local p90=$(echo "$result" | jq -r '.aggregations.percentiles.values["90.0"]' 2>/dev/null)
    local p95=$(echo "$result" | jq -r '.aggregations.percentiles.values["95.0"]' 2>/dev/null)
    local p99=$(echo "$result" | jq -r '.aggregations.percentiles.values["99.0"]' 2>/dev/null)

    if [[ "$p50" != "null" && "$p50" != "" ]]; then
        # 評估效能狀態
        local p95_status="good"
        if (( $(calc "$p95 > 1000") )); then
            p95_status="critical"
        elif (( $(calc "$p95 > 500") )); then
            p95_status="warning"
        fi

        print_metric "P50 (中位數)" "$(printf '%.1f' $p50)" "ms" "info"
        print_metric "P90" "$(printf '%.1f' $p90)" "ms" "info"
        print_metric "P95" "$(printf '%.1f' $p95)" "ms" "$p95_status"
        print_metric "P99" "$(printf '%.1f' $p99)" "ms" "info"
    else
        echo -e "  ${YELLOW}⚠ 無最近1小時的數據${NC}"
    fi
    echo
}

# 獲取效能分數
get_performance_score() {
    print_section "效能分數"

    local result=$(curl -s "$ELASTICSEARCH_URL/$INDEX_PATTERN/_search" -H "Content-Type: application/json" -d '{
        "size": 0,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-1h"
                }
            }
        },
        "aggs": {
            "avg_score": {
                "avg": {
                    "field": "performance_score"
                }
            }
        }
    }')

    local score=$(echo "$result" | jq -r '.aggregations.avg_score.value' 2>/dev/null)

    if [[ "$score" != "null" && "$score" != "" ]]; then
        local status="good"
        if (( $(calc "$score < 60") )); then
            status="critical"
        elif (( $(calc "$score < 80") )); then
            status="warning"
        fi

        print_metric "平均效能分數" "$(printf '%.1f' $score)" "/100" "$status"
    else
        echo -e "  ${YELLOW}⚠ 無效能分數數據${NC}"
    fi
    echo
}

# 獲取SLA指標
get_sla_metrics() {
    print_section "SLA達成率"

    local result=$(curl -s "$ELASTICSEARCH_URL/$INDEX_PATTERN/_search" -H "Content-Type: application/json" -d '{
        "size": 0,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-1h"
                }
            }
        },
        "aggs": {
            "availability": {
                "avg": {
                    "field": "sla_available"
                }
            },
            "performance": {
                "avg": {
                    "field": "sla_performance"
                }
            },
            "overall": {
                "avg": {
                    "field": "sla_met"
                }
            }
        }
    }')

    local availability=$(echo "$result" | jq -r '.aggregations.availability.value' 2>/dev/null)
    local performance=$(echo "$result" | jq -r '.aggregations.performance.value' 2>/dev/null)
    local overall=$(echo "$result" | jq -r '.aggregations.overall.value' 2>/dev/null)

    if [[ "$availability" != "null" && "$availability" != "" ]]; then
        local avail_pct=$(printf '%.1f' $(calc "$availability * 100"))
        local perf_pct=$(printf '%.1f' $(calc "$performance * 100"))
        local overall_pct=$(printf '%.1f' $(calc "$overall * 100"))

        # 評估SLA狀態
        local avail_status="good"
        local perf_status="good"
        local overall_status="good"

        if (( $(calc "$availability < 0.95") )); then
            avail_status="critical"
        fi
        if (( $(calc "$performance < 0.95") )); then
            perf_status="critical"
        fi
        if (( $(calc "$overall < 0.95") )); then
            overall_status="critical"
        fi

        print_metric "可用性SLA" "$avail_pct" "%" "$avail_status"
        print_metric "效能SLA" "$perf_pct" "%" "$perf_status"
        print_metric "綜合SLA" "$overall_pct" "%" "$overall_status"
    else
        echo -e "  ${YELLOW}⚠ 無SLA數據${NC}"
    fi
    echo
}

# 獲取請求統計
get_request_stats() {
    print_section "請求統計 (最近1小時)"

    local result=$(curl -s "$ELASTICSEARCH_URL/$INDEX_PATTERN/_search" -H "Content-Type: application/json" -d '{
        "size": 0,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-1h"
                }
            }
        },
        "aggs": {
            "total_requests": {
                "value_count": {
                    "field": "@timestamp"
                }
            },
            "error_requests": {
                "filter": {
                    "range": {
                        "http_status": {
                            "gte": 400
                        }
                    }
                }
            },
            "status_codes": {
                "terms": {
                    "field": "http_status",
                    "size": 10
                }
            }
        }
    }')

    local total=$(echo "$result" | jq -r '.aggregations.total_requests.value' 2>/dev/null)
    local errors=$(echo "$result" | jq -r '.aggregations.error_requests.doc_count' 2>/dev/null)

    if [[ "$total" != "null" && "$total" != "" ]]; then
        local error_rate=0
        if [[ "$total" -gt 0 ]]; then
            error_rate=$(calc "$errors * 100.0 / $total")
        fi

        local error_status="good"
        if (( $(calc "$error_rate > 5") )); then
            error_status="critical"
        elif (( $(calc "$error_rate > 1") )); then
            error_status="warning"
        fi

        print_metric "總請求數" "$total" "" "info"
        print_metric "錯誤請求數" "$errors" "" "info"
        print_metric "錯誤率" "$(printf '%.2f' $error_rate)" "%" "$error_status"
    else
        echo -e "  ${YELLOW}⚠ 無請求數據${NC}"
    fi
    echo
}

# 獲取服務效能
get_service_performance() {
    print_section "服務效能概覽"

    local result=$(curl -s "$ELASTICSEARCH_URL/$INDEX_PATTERN/_search" -H "Content-Type: application/json" -d '{
        "size": 0,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-1h"
                }
            }
        },
        "aggs": {
            "services": {
                "terms": {
                    "field": "service_name",
                    "size": 10
                },
                "aggs": {
                    "avg_latency": {
                        "avg": {
                            "field": "total_latency"
                        }
                    },
                    "request_count": {
                        "value_count": {
                            "field": "@timestamp"
                        }
                    }
                }
            }
        }
    }')

    local services=$(echo "$result" | jq -r '.aggregations.services.buckets[]' 2>/dev/null)

    if [[ "$services" != "" ]]; then
        echo "$result" | jq -r '.aggregations.services.buckets[] | "  • \(.key): \(.doc_count)次請求, 平均\(.aggs.avg_latency.value | round)ms"' 2>/dev/null
    else
        echo -e "  ${YELLOW}⚠ 無服務數據${NC}"
    fi
    echo
}

# 主函數
main() {
    print_header
    check_elasticsearch
    get_response_time_percentiles
    get_performance_score
    get_sla_metrics
    get_request_stats
    get_service_performance

    echo -e "${BLUE}監控完成${NC}"
}

# 檢查依賴
if ! command -v jq &> /dev/null; then
    echo -e "${RED}錯誤: 需要安裝 jq 工具${NC}"
    exit 1
fi

# 數學計算函數 (替代bc)
calc() {
    python3 -c "print($1)" 2>/dev/null || echo "0"
}

# 執行主函數
main