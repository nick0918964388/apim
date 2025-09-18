#!/bin/bash
# Kong APIM 部署驗證腳本
# Deployment validation script for Kong APIM Platform

set -euo pipefail

echo "===================================================="
echo "Kong APIM Platform - 部署驗證測試"
echo "===================================================="

# 顏色設定
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 測試結果計數器
TESTS_PASSED=0
TESTS_FAILED=0

# 測試函數
test_service() {
    local service_name=$1
    local test_command=$2
    local expected_result=$3
    
    echo -e "${YELLOW}測試: ${service_name}${NC}"
    
    if eval "$test_command"; then
        echo -e "${GREEN}✓ ${service_name} - 測試通過${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ ${service_name} - 測試失敗${NC}"
        ((TESTS_FAILED++))
    fi
    echo ""
}

# 檢查 Docker 是否安裝
echo "1. 環境檢查"
echo "----------------------------------------"
test_service "Docker 安裝檢查" "command -v docker >/dev/null 2>&1" ""
test_service "Docker Compose 安裝檢查" "command -v docker-compose >/dev/null 2>&1 || command -v 'docker compose' >/dev/null 2>&1" ""

# 驗證配置文件
echo "2. 配置文件驗證"
echo "----------------------------------------"
test_service "Docker Compose 配置語法" "cd deployments/docker && docker compose --env-file ../../config/env/.env.dev config >/dev/null 2>&1" ""
test_service "Kong 配置文件" "test -f config/kong/kong.conf" ""
test_service "PostgreSQL Master 配置" "test -f config/postgresql/master/postgresql.conf && test -f config/postgresql/master/pg_hba.conf" ""
test_service "PostgreSQL Slave 配置" "test -f config/postgresql/slave/postgresql.conf && test -f config/postgresql/slave/pg_hba.conf" ""
test_service "Logstash 配置文件" "test -f deployments/monitoring/logstash/kong-logs.conf" ""
test_service "Elasticsearch 配置文件" "test -f deployments/monitoring/elasticsearch/elasticsearch.yml" ""
test_service "Kibana 配置文件" "test -f deployments/monitoring/kibana/kibana.yml" ""

# 驗證腳本
echo "3. 腳本驗證"
echo "----------------------------------------"
test_service "完整備份腳本" "test -x scripts/backup/full_backup.sh" ""
test_service "增量備份腳本" "test -x scripts/backup/incremental_backup.sh" ""
test_service "備份驗證腳本" "test -x scripts/backup/verify_backup.sh" ""
test_service "Slave 初始化腳本" "test -x deployments/docker/scripts/setup-slave.sh" ""

# 如果 Docker 可用，執行容器測試
if command -v docker >/dev/null 2>&1 && docker info >/dev/null 2>&1; then
    echo "4. 容器服務測試"
    echo "----------------------------------------"
    
    # 啟動服務
    echo "啟動 Kong APIM 服務..."
    cd deployments/docker
    docker compose --env-file ../../config/env/.env.dev up -d
    
    # 等待服務就緒
    echo "等待服務啟動..."
    sleep 60
    
    # 測試各個服務
    test_service "PostgreSQL Master 連接" "docker exec kong-database-master pg_isready -U kong" ""
    test_service "PostgreSQL Slave 連接" "docker exec kong-database-slave pg_isready -U kong" ""
    test_service "Elasticsearch 健康檢查" "curl -f http://localhost:9200/_cluster/health" ""
    test_service "Kibana 狀態檢查" "curl -f http://localhost:5601/api/status" ""
    test_service "Kong Admin API" "curl -f http://localhost:8001/status" ""
    test_service "Kong Proxy" "curl -f http://localhost:8000/" ""
    
    # 測試主從複製
    echo "5. PostgreSQL 主從複製測試"
    echo "----------------------------------------"
    test_service "主從複製狀態" "docker exec kong-database-master psql -U kong -d kong -c \"SELECT * FROM pg_stat_replication;\" | grep -q replicator" ""
    
    # 測試數據同步
    docker exec kong-database-master psql -U kong -d kong -c "CREATE TABLE IF NOT EXISTS test_replication (id SERIAL, message TEXT);"
    docker exec kong-database-master psql -U kong -d kong -c "INSERT INTO test_replication (message) VALUES ('replication test');"
    sleep 5
    test_service "主從數據同步" "docker exec kong-database-slave psql -U kong -d kong -c \"SELECT message FROM test_replication WHERE message='replication test';\" | grep -q 'replication test'" ""
    
    # 測試日誌流程
    echo "6. 監控數據流測試"
    echo "----------------------------------------"
    # 觸發一些 API 請求
    curl -s http://localhost:8000/test-endpoint || true
    curl -s http://localhost:8000/another-test || true
    sleep 10
    
    test_service "Logstash 處理數據" "curl -f http://localhost:8080" ""
    test_service "Elasticsearch 索引" "curl -s 'http://localhost:9200/kong-api-logs-*/_search?size=1' | grep -q '\"hits\"'" ""
    
    cd ../..
else
    echo "4. 容器服務測試"
    echo "----------------------------------------"
    echo -e "${YELLOW}Docker 不可用，跳過容器測試${NC}"
fi

# 測試總結
echo "===================================================="
echo "測試總結"
echo "===================================================="
echo -e "通過的測試: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "失敗的測試: ${RED}${TESTS_FAILED}${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 所有測試通過！部署配置正確${NC}"
    exit 0
else
    echo -e "${RED}✗ 有 ${TESTS_FAILED} 個測試失敗，請檢查配置${NC}"
    exit 1
fi