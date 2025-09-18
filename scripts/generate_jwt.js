const crypto = require('crypto');

// JWT配置
const SECRET = "hldev-maximo-secret-2024";
const KEY = "maximo-hldev-key";

// 創建JWT header和payload
const header = {
  "alg": "HS256",
  "typ": "JWT"
};

const payload = {
  "iss": KEY,
  "iat": Math.floor(Date.now() / 1000),
  "exp": Math.floor(Date.now() / 1000) + 3600,
  "sub": "maximo-client"
};

// Base64URL編碼函數
function base64URLEncode(str) {
  return Buffer.from(str)
    .toString('base64')
    .replace(/\+/g, '-')
    .replace(/\//g, '_')
    .replace(/=/g, '');
}

// 創建JWT
const encodedHeader = base64URLEncode(JSON.stringify(header));
const encodedPayload = base64URLEncode(JSON.stringify(payload));
const data = `${encodedHeader}.${encodedPayload}`;

// 生成簽名
const signature = crypto
  .createHmac('sha256', SECRET)
  .update(data)
  .digest('base64')
  .replace(/\+/g, '-')
  .replace(/\//g, '_')
  .replace(/=/g, '');

const token = `${data}.${signature}`;

console.log("JWT Token:");
console.log(token);
console.log("\nCurl命令範例:");
console.log(`curl -X GET http://localhost:8000/api/v1/hldev/pm/workorders \\`);
console.log(`  -H "Authorization: Bearer ${token}"`);