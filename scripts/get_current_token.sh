#!/bin/bash

# 快速取得當前有效的JWT token
echo "=== 當前JWT Token ==="
TOKEN=$(node scripts/kong_jwt_manager.js generate maximo-hldev-api | grep "Token:" | cut -d' ' -f2)
echo "Token: $TOKEN"
echo ""
echo "=== 測試命令 ==="
echo "curl -X GET http://localhost:8000/api/v1/hldev/pm/workorders \\"
echo "  -H \"Authorization: Bearer $TOKEN\""
echo ""
echo "=== 環境變數設定 ==="
echo "export JWT_TOKEN=\"$TOKEN\""