const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = 5000;
const HOST = '0.0.0.0';

const LOADING_PAGE = `<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>隧道启动中...</title>
<style>
  body { background:#020617; color:#e5e7eb; display:flex; align-items:center;
         justify-content:center; height:100vh; margin:0;
         font-family:system-ui,sans-serif; }
  .box { text-align:center; }
  h1 { font-size:2rem; margin-bottom:12px; }
  p  { color:#9ca3af; margin-bottom:24px; }
  .dot { display:inline-block; width:10px; height:10px; border-radius:50%;
         background:#6366f1; margin:0 4px;
         animation: bounce 1.2s infinite ease-in-out; }
  .dot:nth-child(2){ animation-delay:.2s; }
  .dot:nth-child(3){ animation-delay:.4s; }
  @keyframes bounce { 0%,80%,100%{transform:scale(0)} 40%{transform:scale(1)} }
</style>
<meta http-equiv="refresh" content="5">
</head>
<body>
<div class="box">
  <h1>⏳ 隧道启动中</h1>
  <p>正在建立 Cloudflare 隧道，请稍候...</p>
  <span class="dot"></span>
  <span class="dot"></span>
  <span class="dot"></span>
  <p style="margin-top:20px;font-size:13px;color:#6b7280">页面将每 5 秒自动刷新</p>
</div>
</body>
</html>`;

const MIME_TYPES = {
    '.html': 'text/html; charset=utf-8',
    '.js':   'application/javascript; charset=utf-8',
    '.css':  'text/css; charset=utf-8',
    '.json': 'application/json',
};

function sendLoadingPage(res) {
    try {
        if (!res.headersSent) {
            res.writeHead(200, { 'Content-Type': 'text/html; charset=utf-8' });
            res.end(LOADING_PAGE);
        }
    } catch (e) {
        console.error('sendLoadingPage error:', e.message);
    }
}

function serveFile(res, filePath) {
    try {
        if (fs.existsSync(filePath) && fs.statSync(filePath).isFile()) {
            fs.readFile(filePath, (err, data) => {
                if (err) {
                    sendLoadingPage(res);
                    return;
                }
                const ext = path.extname(filePath);
                const contentType = MIME_TYPES[ext] || 'application/octet-stream';
                res.writeHead(200, { 'Content-Type': contentType });
                res.end(data);
            });
        } else {
            sendLoadingPage(res);
        }
    } catch (e) {
        sendLoadingPage(res);
    }
}

const server = http.createServer((req, res) => {
    try {
        res.setHeader('Access-Control-Allow-Origin', '*');
        res.setHeader('Cache-Control', 'no-cache');
        
        let urlPath = req.url.split('?')[0];
        
        // 根路径处理
        if (urlPath === '/' || urlPath === '/index.html') {
            const tunnelPage = path.join(__dirname, 'tunnel_index.html');
            serveFile(res, tunnelPage);
            return;
        }
        
        // 其他路径：尝试作为文件，否则返回 loading 页面
        const filePath = path.join(__dirname, urlPath);
        serveFile(res, filePath);
        
    } catch (err) {
        console.error('Request error:', err.message);
        sendLoadingPage(res);
    }
});

server.on('error', (err) => {
    console.error('Server error:', err.message);
});

server.listen(PORT, HOST, () => {
    console.log(`✅ Server running at http://${HOST}:${PORT}/`);
});
