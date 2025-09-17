# 測試策略 (Testing Strategy)

## 測試層級 (Testing Levels)

### 1. 單元測試 (Unit Testing)
**目標**: 測試個別配置組件的正確性

**測試範圍**:
- Kong 配置檔案語法驗證
- Docker Compose 文件結構驗證
- 環境變數配置完整性檢查

**工具**:
- `yamllint`: YAML 檔案語法檢查
- `docker-compose config`: Docker Compose 配置驗證
- 自定義 shell 腳本進行配置檢查

### 2. 整合測試 (Integration Testing)
**目標**: 測試 Kong 與後端服務的整合

**測試範圍**:
- Kong 服務註冊與發現
- 路由配置正確性
- 插件功能驗證
- 資料庫連接測試

**工具**:
- `curl`: HTTP 請求測試
- `Postman/Newman`: API 測試套件
- Kong Admin API 驗證腳本

### 3. 端到端測試 (End-to-End Testing)
**目標**: 測試完整的 API 管理流程

**測試範圍**:
- 完整的 API 請求流程
- 認證授權流程
- 監控與日誌記錄
- 錯誤處理機制

## 測試類型 (Test Types)

### 功能測試 (Functional Testing)

#### Kong 服務測試
```bash
# 測試服務註冊
curl -i -X POST http://kong-admin:8001/services \
  --data "name=test-service" \
  --data "url=http://backend:3000"

# 驗證服務狀態
curl -i http://kong-admin:8001/services/test-service
```

#### 路由測試
```bash
# 測試路由創建
curl -i -X POST http://kong-admin:8001/services/test-service/routes \
  --data "paths[]=/api/test"

# 驗證路由功能
curl -i http://kong:8000/api/test
```

### 效能測試 (Performance Testing)

#### 負載測試指標
- **併發請求數**: 100-500 併發連接
- **響應時間**: < 100ms (P95)
- **吞吐量**: > 1000 requests/second
- **錯誤率**: < 0.1%

#### 測試工具
- `ab` (Apache Bench): 基本負載測試
- `hey`: 現代 HTTP 負載測試工具
- `wrk`: 高效能 HTTP 基準測試

```bash
# 基本負載測試範例
hey -n 1000 -c 10 http://kong:8000/api/test
```

### 安全測試 (Security Testing)

#### 認證測試
- JWT Token 驗證
- OAuth 2.0 流程測試
- API Key 驗證

#### 授權測試
- Rate Limiting 功能驗證
- CORS 策略測試
- IP 白名單/黑名單測試

## 測試環境 (Test Environments)

### 本地開發測試 (Local Development Testing)
```yaml
# docker-compose.test.yml
version: '3.8'
services:
  kong-test:
    image: kong:latest
    environment:
      KONG_DATABASE: "off"
      KONG_DECLARATIVE_CONFIG: /kong/declarative/kong.yml
      KONG_PROXY_ACCESS_LOG: /dev/stdout
      KONG_ADMIN_ACCESS_LOG: /dev/stdout
      KONG_PROXY_ERROR_LOG: /dev/stderr
      KONG_ADMIN_ERROR_LOG: /dev/stderr
```

### CI/CD 整合測試 (CI/CD Integration Testing)
- 自動化配置驗證
- 回歸測試執行
- 部署前安全掃描

## 測試自動化 (Test Automation)

### 測試腳本結構
```
tests/
├── unit/
│   ├── config-validation.sh     # 配置檔案驗證
│   └── yaml-syntax-check.sh     # YAML 語法檢查
├── integration/
│   ├── kong-service-test.sh     # Kong 服務測試
│   ├── route-functionality.sh   # 路由功能測試
│   └── plugin-verification.sh   # 插件驗證
├── e2e/
│   ├── api-workflow-test.sh     # 完整 API 流程測試
│   └── monitoring-test.sh       # 監控功能測試
└── performance/
    ├── load-test.sh             # 負載測試
    └── stress-test.sh           # 壓力測試
```

### 測試執行順序
1. **配置驗證**: 檢查所有配置檔案語法
2. **服務啟動**: 啟動測試環境
3. **整合測試**: 驗證各組件整合
4. **功能測試**: 測試核心功能
5. **效能測試**: 驗證效能指標
6. **清理環境**: 清理測試環境

## 測試資料管理 (Test Data Management)

### 測試資料集
- 模擬 API 後端服務
- 測試用戶與認證資料
- 效能測試負載資料

### 資料隔離
- 每個測試使用獨立資料
- 測試後自動清理
- 避免測試間相互影響

## 測試報告 (Test Reporting)

### 報告內容
- 測試執行結果摘要
- 失敗測試詳細資訊
- 效能指標統計
- 安全測試結果

### 報告格式
- JUnit XML 格式 (CI/CD 整合)
- HTML 報告 (人類閱讀)
- JSON 格式 (自動化處理)