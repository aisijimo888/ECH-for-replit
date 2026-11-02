Architecture

    Runtime: Node.js 20
    Server: Custom HTTP server (server.js) serving a single-page HTML frontend
    Frontend: public_index.html - a complete static HTML/CSS/JS page (no build step required)
    Port: 5000 (0.0.0.0)

Project Structure

server.js           - Node.js HTTP server, serves on port 5000
public_index.html   - Main frontend HTML (ÉLAN shoe store)
index.html.bak      - Original backup of the frontend HTML
Dockerfile          - Original Docker config (not used in Replit)
Caddyfile           - Original Caddy config (not used in Replit)
start.sh            - Original tunnel startup script (not used in Replit)

Running

The app runs via the "Start application" workflow using:

node server.js

Deployment

Configured for autoscale deployment using:

sh start.sh


## 🚀 快速開始

### 2.透過設定環境變數 (-e) 來客製化服務的運行方式。
隧道项目启动run command
sh start.sh

環境變數	預設值	說明	可選值
在：
Config files
.replit  增加变量：
[userenv]

[userenv.shared]
WSPORT = "7860"
