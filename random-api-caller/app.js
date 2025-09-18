const axios = require('axios');

// ------------------- 設定區 -------------------

// 1. 將您的兩個 API URL 放在這個陣列中
const apis = [
    'http://api.mas4dev.xyz:8000/api/v1/hldev/pm/workorders',
    'http://api.mas4dev.xyz:8000/api/v1/hldev/labor'
];

// 2. 設定共用的 HTTP 標頭 (Headers)
// 注意：這些 token (maxauth, Authorization) 通常有時效性，如果腳本出錯，請先確認 token 是否已過期。
const commonHeaders = {
    'Content-Type': 'application/json',
    'maxauth': 'bWF4YWRtaW46emFxMXhzVzI=',
    'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiI3TlhFVWpGMlhqVW81blBhUmQxalFGdm5SYkVvUzRMWCIsImlhdCI6MTc1ODE2NDE3OSwic3ViIjoibWF4aW1vLWNsaWVudCJ9.djrMTk68T-leh6qluCZM1JJxDsBtqV_AHl29Nb0q2yk',
    'Cookie': 'JSESSIONID=0000bBOAwLosgJ0q3oxKfG9QfSc:-1'
};

// 3. 設定呼叫的間隔時間 (單位：毫秒)
// 10 秒 = 10000 毫秒
const intervalInMs = 10000;

// ------------------- 核心函式 -------------------

/**
 * 隨機選擇一個 API 並發送 GET 請求
 */
async function callRandomApi() {
    try {
        // 從 apis 陣列中隨機選擇一個 URL
        const randomIndex = Math.floor(Math.random() * apis.length);
        const selectedApi = apis[randomIndex];

        // 取得當前時間，方便日誌追蹤
        const currentTime = new Date().toISOString();

        console.log(`[${currentTime}] 準備呼叫 API: ${selectedApi}`);

        // 使用 axios 發送 GET 請求
        const response = await axios.get(selectedApi, {
            headers: commonHeaders
        });

        console.log(`[${currentTime}] 呼叫成功!`);
        console.log(`  - 狀態碼 (Status): ${response.status}`);
        // 為避免洗版，只顯示部分回傳資料，您可以自行決定要不要完整顯示
        console.log(`  - 回傳資料 (Data): ${JSON.stringify(response.data).substring(0, 150)}...`);

    } catch (error) {
        const currentTime = new Date().toISOString();
        console.error(`[${currentTime}] 呼叫失敗!`);

        // 更詳細的錯誤處理
        if (error.response) {
            // 伺服器有回應，但狀態碼不是 2xx (例如 401, 403, 500)
            console.error(`  - 錯誤狀態碼: ${error.response.status}`);
            console.error(`  - 錯誤訊息: ${JSON.stringify(error.response.data)}`);
        } else if (error.request) {
            // 請求已發出，但沒有收到回應 (例如網路問題)
            console.error('  - 錯誤: 未收到伺服器回應。請檢查網路連線或 API 伺服器狀態。');
        } else {
            // 其他設定上的錯誤
            console.error('  - 錯誤訊息:', error.message);
        }
    } finally {
        console.log('--------------------------------------------------');
    }
}

// ------------------- 啟動腳本 -------------------

console.log(`腳本已啟動，將每隔 ${intervalInMs / 1000} 秒隨機呼叫一次 API。`);

// 立即執行第一次，然後再開始計時
callRandomApi();

// 設定計時器，每隔 intervalInMs 時間就執行一次 callRandomApi 函式
setInterval(callRandomApi, intervalInMs);