#!/bin/bash

# Kong API User Behavior Monitor Script
# 用於分析API使用者行為模式和異常檢測

# 設定參數
ELASTICSEARCH_URL="http://localhost:9200"
INDEX_PATTERN="kong-logs-current"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# 顏色定義
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 數學計算函數
calc() {
    python3 -c "print($1)" 2>/dev/null || echo "0"
}

# 輸出函數
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE} Kong API User Behavior Monitor${NC}"
    echo -e "${BLUE} 分析時間: $TIMESTAMP${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

print_section() {
    echo -e "${PURPLE}👥 $1${NC}"
    echo "----------------------------------------"
}

print_user_info() {
    local ip="$1"
    local requests="$2"
    local services="$3"
    local agents="$4"
    local risk="$5"

    case $risk in
        "high")
            echo -e "  ${RED}⚠ HIGH RISK${NC} $ip: ${RED}$requests請求${NC}, $services服務, UA: $agents"
            ;;
        "medium")
            echo -e "  ${YELLOW}⚠ MEDIUM${NC} $ip: ${YELLOW}$requests請求${NC}, $services服務, UA: $agents"
            ;;
        "low")
            echo -e "  ${GREEN}✓ NORMAL${NC} $ip: $requests請求, $services服務, UA: $agents"
            ;;
        *)
            echo -e "  ${NC}• $ip: $requests請求, $services服務, UA: $agents${NC}"
            ;;
    esac
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

# 活躍用戶分析
analyze_active_users() {
    print_section "活躍用戶分析 (最近24小時)"

    local result=$(curl -s "$ELASTICSEARCH_URL/$INDEX_PATTERN/_search" -H "Content-Type: application/json" -d '{
        "size": 0,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-24h"
                }
            }
        },
        "aggs": {
            "total_users": {
                "cardinality": {
                    "field": "client_address"
                }
            },
            "users": {
                "terms": {
                    "field": "client_address",
                    "size": 20,
                    "order": {"request_count": "desc"}
                },
                "aggs": {
                    "request_count": {
                        "value_count": {
                            "field": "@timestamp"
                        }
                    },
                    "unique_services": {
                        "cardinality": {
                            "field": "service_name"
                        }
                    },
                    "unique_user_agents": {
                        "cardinality": {
                            "field": "user_agent.keyword"
                        }
                    },
                    "error_count": {
                        "filter": {
                            "range": {
                                "http_status": {"gte": 400}
                            }
                        }
                    },
                    "top_user_agent": {
                        "terms": {
                            "field": "user_agent.keyword",
                            "size": 1
                        }
                    }
                }
            }
        }
    }')

    local total_users=$(echo "$result" | jq -r '.aggregations.total_users.value' 2>/dev/null)

    if [[ "$total_users" != "null" && "$total_users" != "" ]]; then
        print_metric "總活躍用戶數" "$total_users" "" "info"
        echo
        echo "  Top 用戶排行:"

        echo "$result" | jq -r '.aggregations.users.buckets[] |
            select(.request_count.value > 0) |
            @json' 2>/dev/null | head -10 | while read -r user; do
            local ip=$(echo "$user" | jq -r '.key')
            local requests=$(echo "$user" | jq -r '.request_count.value')
            local services=$(echo "$user" | jq -r '.unique_services.value')
            local ua_count=$(echo "$user" | jq -r '.unique_user_agents.value')
            local errors=$(echo "$user" | jq -r '.error_count.doc_count')
            local top_ua=$(echo "$user" | jq -r '.top_user_agent.buckets[0].key // "unknown"' | cut -c1-30)

            # 風險評估
            local risk="low"
            if [[ "$requests" -gt 500 ]] || [[ "$errors" -gt $(calc "$requests * 0.5") ]] || [[ "$ua_count" -gt 5 ]]; then
                risk="high"
            elif [[ "$requests" -gt 100 ]] || [[ "$errors" -gt $(calc "$requests * 0.2") ]] || [[ "$ua_count" -gt 2 ]]; then
                risk="medium"
            fi

            print_user_info "$ip" "$requests" "$services" "$top_ua..." "$risk"
        done
    else
        echo -e "  ${YELLOW}⚠ 無用戶數據${NC}"
    fi
    echo
}

# 異常行為檢測
detect_anomalies() {
    print_section "異常行為檢測 (最近1小時)"

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
            "high_frequency": {
                "terms": {
                    "field": "client_address",
                    "min_doc_count": 50,
                    "size": 10
                },
                "aggs": {
                    "request_count": {
                        "value_count": {
                            "field": "@timestamp"
                        }
                    },
                    "requests_per_minute": {
                        "bucket_script": {
                            "buckets_path": {"total": "request_count"},
                            "script": "params.total / 60.0"
                        }
                    }
                }
            },
            "suspicious_ips": {
                "terms": {
                    "field": "client_address",
                    "size": 100
                },
                "aggs": {
                    "countries": {
                        "cardinality": {
                            "field": "geoip.country_name"
                        }
                    },
                    "user_agents": {
                        "cardinality": {
                            "field": "user_agent.keyword"
                        }
                    },
                    "request_count": {
                        "value_count": {
                            "field": "@timestamp"
                        }
                    },
                    "error_rate": {
                        "bucket_script": {
                            "buckets_path": {
                                "errors": "errors>_count",
                                "total": "request_count"
                            },
                            "script": "params.total > 0 ? (params.errors / params.total * 100) : 0"
                        }
                    },
                    "errors": {
                        "filter": {
                            "range": {
                                "http_status": {"gte": 400}
                            }
                        }
                    }
                }
            }
        }
    }')

    # 高頻請求檢測
    local high_freq_count=$(echo "$result" | jq -r '.aggregations.high_frequency.buckets | length' 2>/dev/null)

    if [[ "$high_freq_count" -gt 0 ]]; then
        print_metric "高頻請求用戶" "$high_freq_count" "個" "warning"
        echo "  詳細列表:"
        echo "$result" | jq -r '.aggregations.high_frequency.buckets[] |
            "    • " + .key + ": " + (.request_count.value|tostring) + "請求 (" +
            (.requests_per_minute.value|round|tostring) + "req/min)"' 2>/dev/null
    else
        print_metric "高頻請求用戶" "0" "個" "good"
    fi

    # 可疑行為檢測
    echo
    echo "  可疑行為模式:"
    local suspicious_found=0

    echo "$result" | jq -r '.aggregations.suspicious_ips.buckets[]' 2>/dev/null | while read -r bucket; do
        local ip=$(echo "$bucket" | jq -r '.key')
        local countries=$(echo "$bucket" | jq -r '.countries.value')
        local agents=$(echo "$bucket" | jq -r '.user_agents.value')
        local requests=$(echo "$bucket" | jq -r '.request_count.value')
        local error_rate=$(echo "$bucket" | jq -r '.error_rate.value // 0')

        # 檢測異常模式
        local anomaly=""
        if [[ "$countries" -gt 3 ]]; then
            anomaly="地理異常($countries國家)"
            suspicious_found=1
        elif [[ "$agents" -gt 5 ]]; then
            anomaly="設備異常($agents種UA)"
            suspicious_found=1
        elif (( $(calc "$error_rate > 80") )); then
            anomaly="錯誤異常($(printf '%.1f' $error_rate)%)"
            suspicious_found=1
        fi

        if [[ -n "$anomaly" ]]; then
            echo -e "    ${RED}⚠ $ip${NC}: $requests請求, $anomaly"
        fi
    done

    if [[ "$suspicious_found" -eq 0 ]]; then
        echo -e "    ${GREEN}✓ 無異常行為檢測到${NC}"
    fi
    echo
}

# 用戶代理分析
analyze_user_agents() {
    print_section "用戶代理分析"

    local result=$(curl -s "$ELASTICSEARCH_URL/$INDEX_PATTERN/_search" -H "Content-Type: application/json" -d '{
        "size": 0,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-24h"
                }
            }
        },
        "aggs": {
            "browsers": {
                "terms": {
                    "field": "user_agent_parsed.name",
                    "size": 10
                },
                "aggs": {
                    "unique_users": {
                        "cardinality": {
                            "field": "client_address"
                        }
                    }
                }
            },
            "operating_systems": {
                "terms": {
                    "field": "user_agent_parsed.os",
                    "size": 10
                },
                "aggs": {
                    "unique_users": {
                        "cardinality": {
                            "field": "client_address"
                        }
                    }
                }
            },
            "top_user_agents": {
                "terms": {
                    "field": "user_agent.keyword",
                    "size": 5
                },
                "aggs": {
                    "unique_users": {
                        "cardinality": {
                            "field": "client_address"
                        }
                    }
                }
            }
        }
    }')

    echo "  熱門瀏覽器:"
    echo "$result" | jq -r '.aggregations.browsers.buckets[]? |
        "    • " + (.key // "Unknown") + ": " + (.unique_users.value|tostring) + "用戶"' 2>/dev/null || echo "    無數據"

    echo
    echo "  操作系統分布:"
    echo "$result" | jq -r '.aggregations.operating_systems.buckets[]? |
        "    • " + (.key // "Unknown") + ": " + (.unique_users.value|tostring) + "用戶"' 2>/dev/null || echo "    無數據"

    echo
    echo "  完整User-Agent TOP 5:"
    echo "$result" | jq -r '.aggregations.top_user_agents.buckets[]? |
        "    • " + (.key[0:60] // "Unknown") + "... (" + (.unique_users.value|tostring) + "用戶)"' 2>/dev/null || echo "    無數據"
    echo
}

# 地理分布分析
analyze_geography() {
    print_section "地理分布分析"

    local result=$(curl -s "$ELASTICSEARCH_URL/$INDEX_PATTERN/_search" -H "Content-Type: application/json" -d '{
        "size": 0,
        "query": {
            "bool": {
                "must": [
                    {
                        "range": {
                            "@timestamp": {
                                "gte": "now-7d"
                            }
                        }
                    },
                    {
                        "exists": {
                            "field": "geoip.country_name"
                        }
                    }
                ]
            }
        },
        "aggs": {
            "countries": {
                "terms": {
                    "field": "geoip.country_name",
                    "size": 10
                },
                "aggs": {
                    "unique_users": {
                        "cardinality": {
                            "field": "client_address"
                        }
                    },
                    "cities": {
                        "terms": {
                            "field": "geoip.city_name",
                            "size": 3
                        }
                    }
                }
            },
            "geographic_diversity": {
                "cardinality": {
                    "field": "geoip.country_name"
                }
            }
        }
    }')

    local diversity=$(echo "$result" | jq -r '.aggregations.geographic_diversity.value' 2>/dev/null)

    if [[ "$diversity" != "null" && "$diversity" != "" && "$diversity" -gt 0 ]]; then
        print_metric "地理多樣性" "$diversity" "個國家" "info"

        echo
        echo "  國家分布:"
        echo "$result" | jq -r '.aggregations.countries.buckets[]? |
            "    • " + .key + ": " + (.unique_users.value|tostring) + "用戶 [" +
            ([.cities.buckets[].key] | join(", ")) + "]"' 2>/dev/null
    else
        echo -e "  ${YELLOW}⚠ 無地理位置數據 (可能都是內部IP)${NC}"
    fi
    echo
}

# 使用模式分析
analyze_usage_patterns() {
    print_section "使用模式分析"

    local result=$(curl -s "$ELASTICSEARCH_URL/$INDEX_PATTERN/_search" -H "Content-Type: application/json" -d '{
        "size": 0,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-24h"
                }
            }
        },
        "aggs": {
            "service_usage": {
                "terms": {
                    "field": "service_name",
                    "size": 10
                },
                "aggs": {
                    "unique_users": {
                        "cardinality": {
                            "field": "client_address"
                        }
                    },
                    "routes": {
                        "terms": {
                            "field": "route_name",
                            "size": 5
                        }
                    }
                }
            },
            "hourly_distribution": {
                "date_histogram": {
                    "field": "@timestamp",
                    "calendar_interval": "hour"
                },
                "aggs": {
                    "unique_users": {
                        "cardinality": {
                            "field": "client_address"
                        }
                    }
                }
            }
        }
    }')

    echo "  服務使用偏好:"
    echo "$result" | jq -r '.aggregations.service_usage.buckets[]? |
        "    • " + .key + ": " + (.unique_users.value|tostring) + "用戶使用"' 2>/dev/null || echo "    無數據"

    echo
    echo "  最近活躍時段 (小時級):"
    local max_users=0
    local peak_hour=""

    # 找出峰值時段
    while IFS= read -r hour_data; do
        local hour=$(echo "$hour_data" | jq -r '.key_as_string' | cut -c12-13)
        local users=$(echo "$hour_data" | jq -r '.unique_users.value')

        if [[ "$users" -gt "$max_users" ]]; then
            max_users=$users
            peak_hour=$hour
        fi

        if [[ "$users" -gt 0 ]]; then
            echo "    • ${hour}:00 - $users 用戶活躍"
        fi
    done < <(echo "$result" | jq -c '.aggregations.hourly_distribution.buckets[]?' 2>/dev/null)

    if [[ -n "$peak_hour" ]]; then
        echo
        print_metric "峰值時段" "${peak_hour}:00" " ($max_users用戶)" "info"
    fi
    echo
}

# 主函數
main() {
    print_header
    check_elasticsearch
    analyze_active_users
    detect_anomalies
    analyze_user_agents
    analyze_geography
    analyze_usage_patterns

    echo -e "${BLUE}用戶行為分析完成${NC}"
}

# 檢查依賴
if ! command -v jq &> /dev/null; then
    echo -e "${RED}錯誤: 需要安裝 jq 工具${NC}"
    exit 1
fi

# 執行主函數
main