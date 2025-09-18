#!/bin/bash

# Deploy Elasticsearch Watchers for Kong API Monitoring
# This script installs all monitoring alerts into Elasticsearch

set -e

# Configuration
ELASTICSEARCH_URL="http://localhost:9200"
WATCHER_DIR="/home/nickyin/apim/deployments/monitoring/elasticsearch/watchers"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

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

# Function to check if Elasticsearch is available
check_elasticsearch() {
    print_status "檢查Elasticsearch連接..."

    if curl -s "${ELASTICSEARCH_URL}/_cluster/health" > /dev/null 2>&1; then
        print_status "Elasticsearch連接正常"
    else
        print_error "無法連接到Elasticsearch (${ELASTICSEARCH_URL})"
        print_error "請確認Elasticsearch服務正在運行"
        exit 1
    fi
}

# Function to deploy a single watcher
deploy_watcher() {
    local watcher_file="$1"
    local watcher_name=$(basename "$watcher_file" .json)

    print_status "部署Watcher: $watcher_name"

    # Check if watcher already exists
    if curl -s -f "${ELASTICSEARCH_URL}/_watcher/watch/$watcher_name" > /dev/null 2>&1; then
        print_warning "Watcher '$watcher_name' 已存在，將進行更新"
        method="PUT"
    else
        print_status "創建新的Watcher '$watcher_name'"
        method="PUT"
    fi

    # Deploy the watcher
    response=$(curl -s -w "%{http_code}" -X $method \
        "${ELASTICSEARCH_URL}/_watcher/watch/$watcher_name" \
        -H "Content-Type: application/json" \
        -d @"$watcher_file")

    http_code="${response: -3}"
    response_body="${response%???}"

    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        print_status "✓ Watcher '$watcher_name' 部署成功"
    else
        print_error "✗ Watcher '$watcher_name' 部署失败 (HTTP: $http_code)"
        echo "Response: $response_body"
        return 1
    fi
}

# Function to list all deployed watchers
list_watchers() {
    print_status "查詢已部署的Watchers..."

    response=$(curl -s "${ELASTICSEARCH_URL}/_watcher/watch/_search?pretty" \
        -H "Content-Type: application/json" \
        -d '{
            "query": {"match_all": {}},
            "size": 20,
            "_source": ["metadata.description", "metadata.severity", "metadata.category"]
        }')

    echo "$response" | jq -r '.hits.hits[] | "\(.id): \(._source.metadata.description // "No description") [\(._source.metadata.severity // "unknown")|\(._source.metadata.category // "unknown")]"' 2>/dev/null || {
        print_warning "無法解析Watcher列表，raw response:"
        echo "$response"
    }
}

# Function to test watcher execution
test_watcher() {
    local watcher_name="$1"

    print_status "測試Watcher執行: $watcher_name"

    response=$(curl -s -w "%{http_code}" -X POST \
        "${ELASTICSEARCH_URL}/_watcher/watch/$watcher_name/_execute" \
        -H "Content-Type: application/json")

    http_code="${response: -3}"
    response_body="${response%???}"

    if [[ "$http_code" =~ ^2[0-9][0-9]$ ]]; then
        print_status "✓ Watcher '$watcher_name' 測試成功"
        echo "$response_body" | jq '.watch_record.result.condition.met' 2>/dev/null || echo "Test completed"
    else
        print_error "✗ Watcher '$watcher_name' 測試失败 (HTTP: $http_code)"
        echo "Response: $response_body"
    fi
}

# Main deployment function
main() {
    echo "=========================================="
    echo "Kong API監控 - Elasticsearch Watcher部署"
    echo "=========================================="

    # Check prerequisites
    check_elasticsearch

    # Check if watcher directory exists
    if [[ ! -d "$WATCHER_DIR" ]]; then
        print_error "Watcher目錄不存在: $WATCHER_DIR"
        exit 1
    fi

    # Find all watcher JSON files
    watcher_files=($(find "$WATCHER_DIR" -name "*.json" -type f))

    if [[ ${#watcher_files[@]} -eq 0 ]]; then
        print_error "在 $WATCHER_DIR 中未找到Watcher配置文件"
        exit 1
    fi

    print_status "找到 ${#watcher_files[@]} 個Watcher配置文件"

    # Deploy each watcher
    success_count=0
    total_count=${#watcher_files[@]}

    for watcher_file in "${watcher_files[@]}"; do
        if deploy_watcher "$watcher_file"; then
            ((success_count++))
        fi
        echo ""
    done

    echo "=========================================="
    print_status "部署完成: $success_count/$total_count 個Watcher成功部署"
    echo ""

    # List all deployed watchers
    list_watchers

    echo ""
    echo "使用以下指令測試特定Watcher:"
    echo "  $0 test <watcher-name>"
    echo ""
    echo "使用以下指令查看Watcher狀態:"
    echo "  curl ${ELASTICSEARCH_URL}/_watcher/stats?pretty"
}

# Handle command line arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "test")
        if [[ -z "$2" ]]; then
            print_error "請指定要測試的Watcher名稱"
            print_error "用法: $0 test <watcher-name>"
            exit 1
        fi
        check_elasticsearch
        test_watcher "$2"
        ;;
    "list")
        check_elasticsearch
        list_watchers
        ;;
    *)
        echo "用法: $0 [deploy|test <name>|list]"
        echo "  deploy: 部署所有Watchers (預設)"
        echo "  test:   測試指定的Watcher"
        echo "  list:   列出已部署的Watchers"
        exit 1
        ;;
esac