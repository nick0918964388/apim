const crypto = require('crypto');
const { exec } = require('child_process');

class KongJWTManager {
  constructor(adminUrl = 'http://localhost:8001') {
    this.adminUrl = adminUrl;
  }

  // 使用Kong Admin API獲取JWT credentials
  async getJWTCredentials(consumerName) {
    return new Promise((resolve, reject) => {
      exec(`curl -s ${this.adminUrl}/consumers/${consumerName}/jwt`, (error, stdout, stderr) => {
        if (error) {
          reject(error);
          return;
        }
        try {
          const result = JSON.parse(stdout);
          resolve(result.data);
        } catch (e) {
          reject(e);
        }
      });
    });
  }

  // 獲取所有consumers
  async getAllConsumers() {
    return new Promise((resolve, reject) => {
      exec(`curl -s ${this.adminUrl}/consumers`, (error, stdout, stderr) => {
        if (error) {
          reject(error);
          return;
        }
        try {
          const result = JSON.parse(stdout);
          resolve(result.data);
        } catch (e) {
          reject(e);
        }
      });
    });
  }

  // 列出所有環境的credentials
  async listAllCredentials() {
    try {
      const consumers = await this.getAllConsumers();
      const results = [];

      for (const consumer of consumers) {
        if (consumer.username.includes('maximo')) {
          const credentials = await this.getJWTCredentials(consumer.username);
          results.push({
            consumer: consumer.username,
            environment: this.getEnvironmentFromUsername(consumer.username),
            tags: consumer.tags,
            credentials: credentials.map(cred => ({
              key: cred.key,
              id: cred.id,
              tags: cred.tags,
              created: new Date(cred.created_at * 1000).toISOString()
            }))
          });
        }
      }
      return results;
    } catch (error) {
      throw error;
    }
  }

  // 從username推斷環境
  getEnvironmentFromUsername(username) {
    if (username.includes('hldev')) return 'development';
    if (username.includes('test')) return 'test';
    if (username.includes('prod')) return 'production';
    return 'unknown';
  }

  // 生成JWT token
  generateJWT(key, secret, expiresInSeconds = 3600) {
    const header = {
      "alg": "HS256",
      "typ": "JWT"
    };

    const payload = {
      "iss": key,
      "iat": Math.floor(Date.now() / 1000),
      "sub": "maximo-client"
    };

    // 只有當expiresInSeconds > 0時才添加exp claim
    if (expiresInSeconds > 0) {
      payload.exp = Math.floor(Date.now() / 1000) + expiresInSeconds;
    }

    // Base64URL編碼
    const base64URLEncode = (str) => {
      return Buffer.from(str)
        .toString('base64')
        .replace(/\+/g, '-')
        .replace(/\//g, '_')
        .replace(/=/g, '');
    };

    const encodedHeader = base64URLEncode(JSON.stringify(header));
    const encodedPayload = base64URLEncode(JSON.stringify(payload));
    const data = `${encodedHeader}.${encodedPayload}`;

    const signature = crypto
      .createHmac('sha256', secret)
      .update(data)
      .digest('base64')
      .replace(/\+/g, '-')
      .replace(/\//g, '_')
      .replace(/=/g, '');

    return `${data}.${signature}`;
  }

  // 為指定consumer生成token
  async generateTokenForConsumer(consumerName, expiresInSeconds = 3600) {
    try {
      const credentials = await this.getJWTCredentials(consumerName);
      if (credentials.length === 0) {
        throw new Error(`No JWT credentials found for consumer: ${consumerName}`);
      }

      // 使用第一個credential
      const cred = credentials[0];
      const token = this.generateJWT(cred.key, cred.secret, expiresInSeconds);

      const result = {
        token: token,
        key: cred.key
      };

      if (expiresInSeconds > 0) {
        result.expiresAt = new Date(Date.now() + expiresInSeconds * 1000).toISOString();
      } else {
        result.expiresAt = "永不過期 (Never expires)";
      }

      return result;
    } catch (error) {
      throw error;
    }
  }
}

// CLI使用
if (require.main === module) {
  const manager = new KongJWTManager();

  const command = process.argv[2];

  if (command === 'generate') {
    const consumerName = process.argv[3] || 'maximo-hldev-api';
    const expireFlag = process.argv[4];

    // 檢查是否使用永久token
    let expiresInSeconds = 3600; // 預設1小時
    if (expireFlag === '--never-expire' || expireFlag === '--permanent') {
      expiresInSeconds = 0; // 永不過期
    } else if (expireFlag && !isNaN(expireFlag)) {
      expiresInSeconds = parseInt(expireFlag); // 自定義秒數
    }

    manager.generateTokenForConsumer(consumerName, expiresInSeconds)
      .then(result => {
        console.log('JWT Token Generated:');
        console.log('Consumer:', consumerName);
        console.log('Token:', result.token);
        console.log('Key:', result.key);
        console.log('Expires:', result.expiresAt);
        console.log('\nCurl命令:');
        console.log(`curl -X GET http://localhost:8000/api/v1/hldev/pm/workorders \\`);
        console.log(`  -H "Authorization: Bearer ${result.token}"`);
      })
      .catch(error => {
        console.error('Error:', error.message);
      });

  } else if (command === 'list') {
    manager.listAllCredentials()
      .then(results => {
        console.log('=== Kong JWT Credentials ===\n');
        results.forEach(result => {
          console.log(`Consumer: ${result.consumer}`);
          console.log(`Environment: ${result.environment}`);
          console.log(`Tags: ${JSON.stringify(result.tags)}`);
          console.log('Credentials:');
          result.credentials.forEach((cred, index) => {
            console.log(`  ${index + 1}. Key: ${cred.key}`);
            console.log(`     ID: ${cred.id}`);
            console.log(`     Tags: ${JSON.stringify(cred.tags)}`);
            console.log(`     Created: ${cred.created}`);
          });
          console.log('');
        });
      })
      .catch(error => {
        console.error('Error:', error.message);
      });

  } else {
    console.log('Kong JWT管理工具');
    console.log('================');
    console.log('使用方式:');
    console.log('  node scripts/kong_jwt_manager.js generate [consumer-name] [expires]');
    console.log('  node scripts/kong_jwt_manager.js list');
    console.log('');
    console.log('Token過期選項:');
    console.log('  --never-expire   永不過期token');
    console.log('  --permanent      永不過期token (同上)');
    console.log('  3600            自定義過期秒數');
    console.log('  (預設)          1小時過期');
    console.log('');
    console.log('範例:');
    console.log('  node scripts/kong_jwt_manager.js generate maximo-hldev-api');
    console.log('  node scripts/kong_jwt_manager.js generate maximo-hldev-api --never-expire');
    console.log('  node scripts/kong_jwt_manager.js generate maximo-test-api 7200');
    console.log('  node scripts/kong_jwt_manager.js list');
  }
}

module.exports = KongJWTManager;