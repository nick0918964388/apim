# 編碼標準 (Coding Standards)

## 配置管理標準 (Configuration Management Standards)

### YAML 配置格式 (YAML Configuration Format)
```yaml
# Kong 服務配置標準格式
name: service-name
url: http://backend-service:port
protocol: http
port: 80
connect_timeout: 60000
write_timeout: 60000
read_timeout: 60000
```

### 環境變數命名 (Environment Variable Naming)
- 格式: `{COMPONENT}_{SETTING}_{TYPE}`
- 範例: 
  - `KONG_DATABASE_HOST`
  - `POSTGRES_DB_NAME`
  - `ELASTICSEARCH_PORT`

## Docker 標準 (Docker Standards)

### Dockerfile 最佳實踐
- 使用官方基礎映像檔
- 多階段建構減少映像檔大小
- 非 root 使用者執行
- 適當的健康檢查

### Docker Compose 命名規範
- 服務名稱: 小寫字母，用連字符分隔
- 網路名稱: `{project}-{environment}-network`
- 磁碟區名稱: `{service}-{data-type}-volume`

## Kong 配置標準 (Kong Configuration Standards)

### 服務命名規範 (Service Naming Convention)
- 格式: `{domain}-{service}-{version}`
- 範例: `user-auth-v1`, `order-api-v2`

### 路由命名規範 (Route Naming Convention)
- 格式: `{service-name}-{method}-{endpoint}`
- 範例: `user-auth-post-login`, `order-api-get-orders`

### 插件配置標準 (Plugin Configuration Standards)
```yaml
# Rate Limiting Plugin 標準配置
plugins:
- name: rate-limiting
  config:
    minute: 100
    hour: 1000
    policy: local
    hide_client_headers: false
```

## 腳本編寫標準 (Script Writing Standards)

### Shell 腳本標準
- 使用 `#!/bin/bash` shebang
- 啟用嚴格模式: `set -euo pipefail`
- 函數命名: 小寫字母，下劃線分隔
- 變數命名: 大寫字母，下劃線分隔

### 錯誤處理 (Error Handling)
```bash
# 標準錯誤處理模式
if ! command -v docker >/dev/null 2>&1; then
    echo "錯誤: Docker 未安裝" >&2
    exit 1
fi
```

## 文件標準 (Documentation Standards)

### 設定檔註解 (Configuration Comments)
- 使用繁體中文註解
- 每個重要設定包含用途說明
- 預設值與可選值說明

### README 文件結構
1. 專案描述
2. 安裝需求
3. 快速開始
4. 設定說明
5. 故障排除

## 安全標準 (Security Standards)

### 敏感資訊處理
- 使用環境變數存儲敏感資訊
- 禁止在配置檔案中硬編碼密碼
- 使用 Docker secrets 管理敏感資料

### 存取控制
- 最小權限原則
- 定期輪換憑證
- 啟用適當的日誌記錄

## 版本控制標準 (Version Control Standards)

### 提交訊息格式
- 格式: `{type}: {description}`
- 類型: feat, fix, docs, config, test
- 範例: `feat: 新增 Kong 服務配置`

### 分支命名規範
- 功能分支: `feature/{story-number}-{description}`
- 修復分支: `fix/{issue-number}-{description}`
- 配置分支: `config/{component}-{description}`