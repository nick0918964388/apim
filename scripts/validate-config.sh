#!/bin/bash
# Kong APIM 配置文件驗證腳本（不需要 Docker）
# Configuration validation script for Kong APIM Platform (Docker-free)

set -euo pipefail

echo "===================================================="
echo "Kong APIM Platform - 配置文件驗證"
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
test_config() {
    local test_name=$1
    local test_command=$2
    
    echo -e "${YELLOW}測試: ${test_name}${NC}"
    
    if eval "$test_command"; then
        echo -e "${GREEN}✓ ${test_name} - 通過${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ ${test_name} - 失敗${NC}"
        ((TESTS_FAILED++))
    fi
    echo ""
}

echo "1. 目錄結構驗證"
echo "----------------------------------------"
test_config "deployments/docker 目錄" "test -d deployments/docker"
test_config "config/kong 目錄" "test -d config/kong"
test_config "config/postgresql 目錄" "test -d config/postgresql"
test_config "scripts/backup 目錄" "test -d scripts/backup"
test_config "監控配置目錄" "test -d deployments/monitoring"

echo "2. Kong 配置文件"
echo "----------------------------------------"
test_config "Kong 主配置文件" "test -f config/kong/kong.conf"
test_config "Kong 環境配置" "test -f config/env/.env.dev"

echo "3. PostgreSQL 配置文件"
echo "----------------------------------------"
test_config "Master postgresql.conf" "test -f config/postgresql/master/postgresql.conf"
test_config "Master pg_hba.conf" "test -f config/postgresql/master/pg_hba.conf"
test_config "Slave postgresql.conf" "test -f config/postgresql/slave/postgresql.conf"
test_config "Slave pg_hba.conf" "test -f config/postgresql/slave/pg_hba.conf"
test_config "複製初始化腳本" "test -f scripts/postgresql/init-replication.sql"

echo "4. ELK 配置文件"
echo "----------------------------------------"
test_config "Elasticsearch 配置" "test -f deployments/monitoring/elasticsearch/elasticsearch.yml"
test_config "Logstash 配置" "test -f deployments/monitoring/logstash/kong-logs.conf"
test_config "Logstash 索引模板" "test -f deployments/monitoring/logstash/kong-template.json"
test_config "Kibana 配置" "test -f deployments/monitoring/kibana/kibana.yml"

echo "5. 備份腳本"
echo "----------------------------------------"
test_config "完整備份腳本存在" "test -f scripts/backup/full_backup.sh"
test_config "完整備份腳本可執行" "test -x scripts/backup/full_backup.sh"
test_config "增量備份腳本存在" "test -f scripts/backup/incremental_backup.sh"
test_config "增量備份腳本可執行" "test -x scripts/backup/incremental_backup.sh"
test_config "備份驗證腳本存在" "test -f scripts/backup/verify_backup.sh"
test_config "備份驗證腳本可執行" "test -x scripts/backup/verify_backup.sh"

echo "6. Docker 配置文件"
echo "----------------------------------------"
test_config "Docker Compose 主文件" "test -f deployments/docker/docker-compose.yml"
test_config "Slave 設置腳本" "test -f deployments/docker/scripts/setup-slave.sh"
test_config "Slave 設置腳本可執行" "test -x deployments/docker/scripts/setup-slave.sh"

echo "7. 配置文件語法檢查"
echo "----------------------------------------"

# 檢查 Kong 配置語法
if command -v kong >/dev/null 2>&1; then
    test_config "Kong 配置語法" "kong check config/kong/kong.conf"
else
    echo -e "${YELLOW}Kong CLI 不可用，跳過語法檢查${NC}"
fi

# 檢查 YAML 語法
if command -v yamllint >/dev/null 2>&1; then
    test_config "Docker Compose YAML 語法" "yamllint deployments/docker/docker-compose.yml"
    test_config "Elasticsearch YAML 語法" "yamllint deployments/monitoring/elasticsearch/elasticsearch.yml"
    test_config "Kibana YAML 語法" "yamllint deployments/monitoring/kibana/kibana.yml"
else
    echo -e "${YELLOW}yamllint 不可用，跳過 YAML 語法檢查${NC}"
fi

# 檢查 JSON 語法
if command -v jq >/dev/null 2>&1; then
    test_config "Logstash JSON 模板語法" "jq . deployments/monitoring/logstash/kong-template.json >/dev/null"
else
    echo -e "${YELLOW}jq 不可用，跳過 JSON 語法檢查${NC}"
fi

echo "8. 環境變數檢查"
echo "----------------------------------------"
test_config "環境變數文件包含必要配置" "grep -q 'KONG_DATABASE=' config/env/.env.dev && grep -q 'POSTGRES_PASSWORD=' config/env/.env.dev"

# 測試總結
echo "===================================================="
echo "配置驗證總結"
echo "===================================================="
echo -e "通過的測試: ${GREEN}${TESTS_PASSED}${NC}"
echo -e "失敗的測試: ${RED}${TESTS_FAILED}${NC}"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}✓ 所有配置驗證通過！${NC}"
    exit 0
else
    echo -e "${RED}✗ 有 ${TESTS_FAILED} 個配置測試失敗${NC}"
    exit 1
fi