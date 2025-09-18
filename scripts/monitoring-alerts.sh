#!/bin/bash

# Kong API監控告警系統 (替代Elasticsearch Watcher)
# 由於Elasticsearch Watcher需要付費授權，此腳本提供基於Elasticsearch查詢的告警功能

set -e

# Configuration
ELASTICSEARCH_URL="http://localhost:9200"
INDEX_NAME="kong-logs-current"
ALERT_LOG="/var/log/kong-alerts.log"
WEBHOOK_URL="http://localhost:8080/alerts"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Thresholds
ERROR_RATE_THRESHOLD=10       # Error rate threshold (%)
RESPONSE_TIME_THRESHOLD=2000  # P95 response time threshold (ms)
HIGH_FREQ_THRESHOLD=500       # High frequency requests threshold (per 5min)
AVAILABILITY_THRESHOLD=95     # Service availability threshold (%)

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_alert() {
    echo -e "${RED}[ALERT]${NC} $1"
}

# Function to log alerts
log_alert() {
    local alert_type="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo "[$timestamp] [$alert_type] $message" >> "$ALERT_LOG"
    print_alert "$alert_type: $message"
}

# Function to send webhook notification
send_webhook() {
    local alert_data="$1"

    if command -v curl > /dev/null 2>&1; then
        curl -s -X POST "$WEBHOOK_URL" \
            -H "Content-Type: application/json" \
            -d "$alert_data" > /dev/null 2>&1 || {
            print_warning "無法發送Webhook通知到 $WEBHOOK_URL"
        }
    fi
}

# Function to check Elasticsearch connectivity
check_elasticsearch() {
    if ! curl -s "${ELASTICSEARCH_URL}/_cluster/health" > /dev/null 2>&1; then
        print_error "無法連接到Elasticsearch (${ELASTICSEARCH_URL})"
        return 1
    fi
    return 0
}

# Function to execute Elasticsearch query
execute_query() {
    local query="$1"

    curl -s -X POST "${ELASTICSEARCH_URL}/${INDEX_NAME}/_search" \
        -H "Content-Type: application/json" \
        -d "$query"
}

# Alert 1: Error Rate Monitor
check_error_rate() {
    print_status "檢查錯誤率..."

    local query='{
        "size": 0,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-5m"
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
            }
        }
    }'

    local response=$(execute_query "$query")
    local total=$(echo "$response" | jq -r '.aggregations.total_requests.value // 0')
    local errors=$(echo "$response" | jq -r '.aggregations.error_requests.doc_count // 0')

    if [[ "$total" -gt 0 ]]; then
        local error_rate=$(python3 -c "print(round($errors / $total * 100, 2))")

        if (( $(echo "$error_rate > $ERROR_RATE_THRESHOLD" | bc -l) )); then
            local alert_message="錯誤率過高: ${error_rate}% (${errors}/${total}) 超過閾值 ${ERROR_RATE_THRESHOLD}%"
            log_alert "ERROR_RATE" "$alert_message"

            local webhook_data=$(cat <<EOF
{
    "alert_type": "error_rate",
    "severity": "critical",
    "message": "$alert_message",
    "details": {
        "error_rate": $error_rate,
        "total_requests": $total,
        "error_requests": $errors,
        "threshold": $ERROR_RATE_THRESHOLD
    }
}
EOF
)
            send_webhook "$webhook_data"
        else
            print_status "錯誤率正常: ${error_rate}% (${errors}/${total})"
        fi
    else
        print_status "最近5分鐘無請求記錄"
    fi
}

# Alert 2: Response Time Monitor
check_response_time() {
    print_status "檢查響應時間..."

    local query='{
        "size": 0,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-5m"
                }
            }
        },
        "aggs": {
            "p95_response_time": {
                "percentiles": {
                    "field": "total_latency",
                    "percents": [95]
                }
            },
            "avg_response_time": {
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
    }'

    local response=$(execute_query "$query")
    local p95=$(echo "$response" | jq -r '.aggregations.p95_response_time.values."95.0" // 0')
    local avg=$(echo "$response" | jq -r '.aggregations.avg_response_time.value // 0')
    local count=$(echo "$response" | jq -r '.aggregations.request_count.value // 0')

    if [[ "$count" -gt 0 ]] && (( $(echo "$p95 > $RESPONSE_TIME_THRESHOLD" | bc -l) )); then
        local alert_message="P95響應時間過高: ${p95}ms 超過閾值 ${RESPONSE_TIME_THRESHOLD}ms (平均: ${avg}ms)"
        log_alert "RESPONSE_TIME" "$alert_message"

        local webhook_data=$(cat <<EOF
{
    "alert_type": "response_time",
    "severity": "warning",
    "message": "$alert_message",
    "details": {
        "p95_response_time": $p95,
        "avg_response_time": $avg,
        "request_count": $count,
        "threshold": $RESPONSE_TIME_THRESHOLD
    }
}
EOF
)
        send_webhook "$webhook_data"
    else
        if [[ "$count" -gt 0 ]]; then
            print_status "響應時間正常: P95=${p95}ms, 平均=${avg}ms"
        fi
    fi
}

# Alert 3: High Frequency Monitor
check_high_frequency() {
    print_status "檢查高頻請求..."

    local query='{
        "size": 0,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-5m"
                }
            }
        },
        "aggs": {
            "high_frequency_users": {
                "terms": {
                    "field": "client_address",
                    "min_doc_count": '$HIGH_FREQ_THRESHOLD',
                    "size": 10
                },
                "aggs": {
                    "request_count": {
                        "value_count": {
                            "field": "@timestamp"
                        }
                    }
                }
            }
        }
    }'

    local response=$(execute_query "$query")
    local suspicious_ips=$(echo "$response" | jq -r '.aggregations.high_frequency_users.buckets[] | "\(.key):\(.request_count.value)"' | paste -sd "," -)
    local ip_count=$(echo "$response" | jq -r '.aggregations.high_frequency_users.buckets | length')

    if [[ "$ip_count" -gt 0 ]]; then
        local alert_message="檢測到高頻請求異常: ${ip_count}個IP在5分鐘內超過${HIGH_FREQ_THRESHOLD}次請求"
        log_alert "HIGH_FREQUENCY" "$alert_message"

        local webhook_data=$(cat <<EOF
{
    "alert_type": "high_frequency",
    "severity": "critical",
    "message": "$alert_message",
    "details": {
        "suspicious_ips": "$suspicious_ips",
        "ip_count": $ip_count,
        "threshold": $HIGH_FREQ_THRESHOLD
    }
}
EOF
)
        send_webhook "$webhook_data"
    else
        print_status "未檢測到高頻請求異常"
    fi
}

# Alert 4: Service Availability Monitor
check_service_availability() {
    print_status "檢查服務可用性..."

    local query='{
        "size": 0,
        "query": {
            "range": {
                "@timestamp": {
                    "gte": "now-10m"
                }
            }
        },
        "aggs": {
            "services": {
                "terms": {
                    "field": "service_name",
                    "size": 20
                },
                "aggs": {
                    "total_requests": {
                        "value_count": {
                            "field": "@timestamp"
                        }
                    },
                    "successful_requests": {
                        "filter": {
                            "range": {
                                "http_status": {
                                    "lt": 400
                                }
                            }
                        }
                    },
                    "last_request": {
                        "max": {
                            "field": "@timestamp"
                        }
                    }
                }
            }
        }
    }'

    local response=$(execute_query "$query")
    local current_time=$(date +%s)000  # milliseconds
    local alerts_found=false

    echo "$response" | jq -r '.aggregations.services.buckets[]' | while read -r bucket; do
        local service_name=$(echo "$bucket" | jq -r '.key')
        local total=$(echo "$bucket" | jq -r '.total_requests.value')
        local successful=$(echo "$bucket" | jq -r '.successful_requests.doc_count')
        local last_request=$(echo "$bucket" | jq -r '.last_request.value')

        if [[ "$total" -gt 0 ]]; then
            local availability=$(python3 -c "print(round($successful / $total * 100, 2))")
            local minutes_since_last=$(python3 -c "print(round(($current_time - $last_request) / 60000, 1))")

            # Check availability
            if (( $(echo "$availability < $AVAILABILITY_THRESHOLD" | bc -l) )) && [[ "$total" -gt 10 ]]; then
                local alert_message="服務 $service_name 可用性低: ${availability}% (${successful}/${total})"
                log_alert "SERVICE_AVAILABILITY" "$alert_message"
                alerts_found=true
            fi

            # Check if service is down (no requests in last 5 minutes)
            if (( $(echo "$minutes_since_last > 5" | bc -l) )) && [[ "$total" -lt 5 ]]; then
                local alert_message="服務 $service_name 可能停機: ${minutes_since_last}分鐘無活動"
                log_alert "SERVICE_DOWN" "$alert_message"
                alerts_found=true
            fi
        fi
    done

    if [[ "$alerts_found" != true ]]; then
        print_status "所有服務可用性正常"
    fi
}

# Main monitoring function
run_monitoring() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "=========================================="
    echo "Kong API 監控檢查 - $timestamp"
    echo "=========================================="

    if ! check_elasticsearch; then
        print_error "監控檢查失败: Elasticsearch無法連接"
        return 1
    fi

    check_error_rate
    echo ""
    check_response_time
    echo ""
    check_high_frequency
    echo ""
    check_service_availability

    echo ""
    echo "監控檢查完成 - $timestamp"
    echo "=========================================="
}

# Setup function
setup_monitoring() {
    print_status "設置監控告警系統..."

    # Create alert log file
    sudo mkdir -p $(dirname "$ALERT_LOG")
    sudo touch "$ALERT_LOG"
    sudo chmod 666 "$ALERT_LOG"

    # Create cron job for continuous monitoring
    local cron_entry="*/5 * * * * /home/nickyin/apim/scripts/monitoring-alerts.sh run >> /var/log/kong-monitoring.log 2>&1"

    if ! crontab -l 2>/dev/null | grep -q "monitoring-alerts.sh"; then
        (crontab -l 2>/dev/null; echo "$cron_entry") | crontab -
        print_status "已添加Cron任務: 每5分鐘執行監控檢查"
    else
        print_warning "Cron任務已存在"
    fi

    print_status "監控告警系統設置完成"
    print_status "告警日誌位置: $ALERT_LOG"
    print_status "監控日誌位置: /var/log/kong-monitoring.log"
}

# Show help
show_help() {
    echo "Kong API 監控告警系統"
    echo ""
    echo "用法: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  run     - 執行一次監控檢查 (預設)"
    echo "  setup   - 設置監控系統 (Cron任務)"
    echo "  logs    - 查看告警日誌"
    echo "  status  - 查看監控狀態"
    echo "  help    - 顯示此說明"
    echo ""
    echo "監控項目:"
    echo "  - 錯誤率監控 (閾值: ${ERROR_RATE_THRESHOLD}%)"
    echo "  - 響應時間監控 (P95閾值: ${RESPONSE_TIME_THRESHOLD}ms)"
    echo "  - 高頻請求監控 (閾值: ${HIGH_FREQ_THRESHOLD}次/5分鐘)"
    echo "  - 服務可用性監控 (閾值: ${AVAILABILITY_THRESHOLD}%)"
}

# Handle command line arguments
case "${1:-run}" in
    "run")
        run_monitoring
        ;;
    "setup")
        setup_monitoring
        ;;
    "logs")
        if [[ -f "$ALERT_LOG" ]]; then
            tail -n 50 "$ALERT_LOG"
        else
            print_warning "告警日誌文件不存在: $ALERT_LOG"
        fi
        ;;
    "status")
        print_status "監控系統狀態:"
        echo "Elasticsearch: $(curl -s ${ELASTICSEARCH_URL}/_cluster/health | jq -r '.status // "unknown"')"
        echo "告警日誌: $(wc -l < "$ALERT_LOG" 2>/dev/null || echo "0") 條記錄"
        echo "Cron任務: $(crontab -l 2>/dev/null | grep -q "monitoring-alerts.sh" && echo "已設置" || echo "未設置")"
        ;;
    "help"|"-h"|"--help")
        show_help
        ;;
    *)
        print_error "未知命令: $1"
        show_help
        exit 1
        ;;
esac