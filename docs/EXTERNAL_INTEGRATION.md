# Kong APIM外部系統整合指南

## 概述

本文檔提供外部系統與Kong APIM平台整合的完整指南，包括JWT認證、API使用說明和安全配置。

## API端點資訊

### Maximo工單API
- **端點**: `http://your-kong-gateway:8000/api/v1/hldev/pm/workorders`
- **方法**: GET
- **認證**: JWT Bearer Token
- **用途**: 取得預防性維護工單清單

### Maximo人員清單API
- **端點**: `http://your-kong-gateway:8000/api/v1/hldev/labor`
- **方法**: GET
- **認證**: JWT Bearer Token
- **用途**: 取得行動應用人員清單

## 認證方式

### JWT (JSON Web Token) 認證

本平台使用JWT Bearer Token進行API認證。每個環境都有獨立的Consumer和Credentials。

#### 環境分類

| 環境 | Consumer Name | 用途 |
|------|---------------|------|
| 開發環境 | `maximo-hldev-api` | 開發和測試整合 |
| 測試環境 | `maximo-test-api` | UAT和集成測試 |
| 生產環境 | `maximo-prod-api` | 生產環境使用 |

#### JWT配置參數

```json
{
  "algorithm": "HS256",
  "key_claim_name": "iss",
  "claims_to_verify": ["exp"],
  "maximum_expiration": 3600,
  "header_names": ["authorization"]
}
```

## 使用方式

### 1. 生成JWT Token

聯繫API管理員取得以下資訊：
- **Key**: 32字符的唯一識別碼
- **Secret**: 32字符的簽名密鑰

### 2. JWT Token結構

```javascript
// Header
{
  "alg": "HS256",
  "typ": "JWT"
}

// Payload
{
  "iss": "your-provided-key",      // 必須與提供的Key相符
  "iat": 1726624000,              // Token簽發時間 (Unix timestamp)
  "exp": 1726627600,              // Token過期時間 (最多1小時後)
  "sub": "your-consumer-name"     // Consumer識別 (可選)
}
```

### 3. 程式碼範例

#### Node.js範例
```javascript
const jwt = require('jsonwebtoken');
const axios = require('axios');

// JWT配置 (由API管理員提供)
const JWT_KEY = "your-provided-key";
const JWT_SECRET = "your-provided-secret";

// 生成JWT Token
function generateJWT() {
  const payload = {
    iss: JWT_KEY,
    iat: Math.floor(Date.now() / 1000),
    exp: Math.floor(Date.now() / 1000) + 3600, // 1小時後過期
    sub: "your-system-name"
  };

  return jwt.sign(payload, JWT_SECRET, { algorithm: 'HS256' });
}

// 調用工單API
async function getWorkOrders() {
  try {
    const token = generateJWT();

    const response = await axios.get(
      'http://your-kong-gateway:8000/api/v1/hldev/pm/workorders',
      {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      }
    );

    return response.data;
  } catch (error) {
    console.error('API調用失敗:', error.response?.data || error.message);
    throw error;
  }
}

// 調用人員清單API
async function getLaborList() {
  try {
    const token = generateJWT();

    const response = await axios.get(
      'http://your-kong-gateway:8000/api/v1/hldev/labor',
      {
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        }
      }
    );

    return response.data;
  } catch (error) {
    console.error('API調用失敗:', error.response?.data || error.message);
    throw error;
  }
}
```

#### Python範例
```python
import jwt
import time
import requests
from datetime import datetime, timedelta

# JWT配置 (由API管理員提供)
JWT_KEY = "your-provided-key"
JWT_SECRET = "your-provided-secret"

def generate_jwt():
    """生成JWT Token"""
    payload = {
        'iss': JWT_KEY,
        'iat': int(time.time()),
        'exp': int(time.time()) + 3600,  # 1小時後過期
        'sub': 'your-system-name'
    }

    return jwt.encode(payload, JWT_SECRET, algorithm='HS256')

def get_work_orders():
    """取得工單清單"""
    try:
        token = generate_jwt()

        headers = {
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json'
        }

        response = requests.get(
            'http://your-kong-gateway:8000/api/v1/hldev/pm/workorders',
            headers=headers
        )

        response.raise_for_status()
        return response.json()

    except requests.exceptions.RequestException as e:
        print(f'API調用失敗: {e}')
        raise

def get_labor_list():
    """取得人員清單"""
    try:
        token = generate_jwt()

        headers = {
            'Authorization': f'Bearer {token}',
            'Content-Type': 'application/json'
        }

        response = requests.get(
            'http://your-kong-gateway:8000/api/v1/hldev/labor',
            headers=headers
        )

        response.raise_for_status()
        return response.json()

    except requests.exceptions.RequestException as e:
        print(f'API調用失敗: {e}')
        raise
```

#### cURL範例
```bash
#!/bin/bash

# 需要先使用JWT library生成token，或聯繫管理員取得臨時token
TOKEN="your-generated-jwt-token"

# 取得工單清單
curl -X GET "http://your-kong-gateway:8000/api/v1/hldev/pm/workorders" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json"

# 取得人員清單
curl -X GET "http://your-kong-gateway:8000/api/v1/hldev/labor" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "Content-Type: application/json"
```

## 速率限制

為保護系統穩定性，API實施以下速率限制：

- **每分鐘**: 100次請求
- **每小時**: 1000次請求
- **每天**: 10000次請求

超過限制時會收到HTTP 429錯誤。

## 錯誤處理

### 常見錯誤碼

| 錯誤碼 | 說明 | 解決方案 |
|--------|------|----------|
| 401 | JWT認證失敗 | 檢查token格式和簽名 |
| 403 | 權限不足 | 聯繫管理員確認權限 |
| 429 | 速率限制 | 降低請求頻率 |
| 500 | 服務器錯誤 | 聯繫技術支援 |

### JWT認證錯誤
```json
{
  "message": "Unauthorized"
}
```

### 速率限制錯誤
```json
{
  "message": "API rate limit exceeded"
}
```

## 安全建議

1. **保護Credentials**: 將Key和Secret存儲在環境變數或安全的配置管理系統中
2. **Token有效期**: 建議設置較短的Token有效期（1小時以內）
3. **HTTPS**: 生產環境必須使用HTTPS
4. **錯誤處理**: 實作適當的重試機制和錯誤處理
5. **監控**: 監控API使用情況和錯誤率

## 監控和日誌

- 所有API請求都會被記錄到 `/srv/apim/logs/maximo-api.log`
- 包含請求時間、來源IP、Consumer資訊、回應狀態等
- 可用於問題排查和使用分析

## 聯繫資訊

如有技術問題或需要協助，請聯繫：

- **API管理團隊**: api-team@company.com
- **技術支援**: tech-support@company.com
- **緊急聯繫**: +886-xxx-xxxx-xxx

## 附錄

### JWT除錯工具
- 線上JWT除錯: https://jwt.io/
- JWT library文檔:
  - Node.js: https://github.com/auth0/node-jsonwebtoken
  - Python: https://pyjwt.readthedocs.io/

### 測試環境
- 開發環境Gateway: http://dev-kong.company.com:8000
- 測試環境Gateway: http://test-kong.company.com:8000
- 生產環境Gateway: https://api.company.com

---

**版本**: 1.0
**更新日期**: 2025-09-18
**維護人員**: Kong APIM Team