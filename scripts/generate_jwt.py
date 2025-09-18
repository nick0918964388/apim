#!/usr/bin/env python3
import jwt
import time
from datetime import datetime, timedelta

# JWT配置 (從Kong配置中取得)
SECRET = "hldev-maximo-secret-2024"
KEY = "maximo-hldev-key"

# 創建JWT payload
payload = {
    "iss": KEY,  # issuer (key claim name)
    "iat": int(time.time()),  # issued at
    "exp": int(time.time()) + 3600,  # expires in 1 hour
    "sub": "maximo-client"  # subject
}

# 生成JWT token
token = jwt.encode(payload, SECRET, algorithm="HS256")

print("JWT Token:")
print(token)
print("\nCurl命令範例:")
print(f'curl -X GET http://localhost:8000/api/v1/hldev/pm/workorders \\')
print(f'  -H "Authorization: Bearer {token}"')