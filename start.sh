#!/bin/sh

# ================= 配置 =================
ARGO_DOMAIN="${ARGO_DOMAIN:-}"
ARGO_AUTH="${ARGO_AUTH:-}"
ARGO_PORT="${ARGO_PORT:-8001}"
IPS="${IPS:-4}"
OPERA="${OPERA:-0}"
COUNTRY="${COUNTRY:-AM}"

# ================= 工具 =================
get_free_port() {
    random=$(od -An -N2 -tu2 /dev/urandom | tr -d ' ')
    echo $(( ( random % 20000 ) + 10000 ))
}

# ================= 隧道设置（后台运行）=================
setup_tunnel() {
    echo "--- 清理旧二进制 ---"
    rm -f ech-server-linux opera-linux cloudflared-linux

    echo "--- 下载二进制 ---"
    ARCH=$(uname -m)
    case "$ARCH" in
        x86_64|amd64)
            ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-amd64"
            OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.16.0/opera-proxy.linux-amd64"
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
            ;;
        i386|i686)
            ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-386"
            OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.16.0/opera-proxy.linux-386"
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-386"
            ;;
        arm64|aarch64)
            ECH_URL="https://github.com/webappstars/ech-hug/releases/download/3.0/ech-tunnel-linux-arm64"
            OPERA_URL="https://github.com/Alexey71/opera-proxy/releases/download/v1.16.0/opera-proxy.linux-arm64"
            CLOUDFLARED_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
            ;;
        *)
            echo "❌ 不支持的架构: $ARCH"
            return 1
            ;;
    esac

    curl -fsSL --retry 2 --connect-timeout 10 --max-time 120 "$ECH_URL" -o ech-server-linux || { echo "❌ 下载 ECH 失败"; return 1; }
    if [ "$OPERA" = "1" ]; then
        curl -fsSL --retry 2 --connect-timeout 10 --max-time 120 "$OPERA_URL" -o opera-linux || { echo "❌ 下载 Opera 失败"; return 1; }
        chmod +x opera-linux
    fi
    curl -fsSL --retry 2 --connect-timeout 10 --max-time 120 "$CLOUDFLARED_URL" -o cloudflared-linux || { echo "❌ 下载 Cloudflared 失败"; return 1; }
    chmod +x ech-server-linux cloudflared-linux

    # ================= 端口 =================
    WSPORT=${WSPORT:-$(get_free_port)}
    ECHPORT=$((WSPORT + 1))
    echo "WS: $WSPORT  ECH: $ECHPORT"

    # ================= Opera =================
    if [ "$OPERA" = "1" ]; then
        COUNTRY=$(echo "$COUNTRY" | tr 'a-z' 'A-Z')
        operaport=$(get_free_port)
        echo "启动 Opera Proxy (port:$operaport, country:$COUNTRY)"
        nohup ./opera-linux -country "$COUNTRY" -socks-mode \
            -bind-address "127.0.0.1:$operaport" >/dev/null 2>&1 &
    fi

    # ================= ECH =================
    sleep 1
    ECH_ARGS="./ech-server-linux -l ws://0.0.0.0:$ECHPORT"
    [ -n "$TOKEN" ] && ECH_ARGS="$ECH_ARGS -token $TOKEN"
    [ "$OPERA" = "1" ] && ECH_ARGS="$ECH_ARGS -f socks5://127.0.0.1:$operaport"

    echo "启动 ECH Server..."
    nohup sh -c "$ECH_ARGS" >/dev/null 2>&1 &

    i=0
    while [ $i -lt 15 ]; do
        (bash -c "echo >/dev/tcp/127.0.0.1/$ECHPORT" 2>/dev/null) && break
        sleep 1
        i=$((i+1))
    done

    if [ $i -eq 15 ]; then
        echo "❌ ECH 未监听端口 $ECHPORT"
        return 1
    fi

    # ================= Cloudflared =================
    echo "启动 Cloudflared..."
    CLOUDFLARED_LOG="/tmp/cloudflared.log"
    ARGO_ARGS="--protocol http2"

    if [ -n "$ARGO_AUTH" ]; then
        ARGO_AUTH_FILE="/tmp/argo_auth.json"
        echo "$ARGO_AUTH" > "$ARGO_AUTH_FILE"
        chmod 600 "$ARGO_AUTH_FILE"
        ARGO_ARGS="$ARGO_ARGS --credentials-file $ARGO_AUTH_FILE"
    fi

    [ -n "$ARGO_DOMAIN" ] && ARGO_ARGS="$ARGO_ARGS --hostname $ARGO_DOMAIN"

    # ⭐ 关键：cloudflared 不使用 HTTP 代理，直接连接 Cloudflare
    # 使用 env -u 清除代理环境变量，避免 i/o timeout
    # ⭐ 注意：--url 不能加 http:// 前缀，否则 ECH WebSocket 服务器会拒绝连接
    echo "启动 Cloudflared (清除代理环境)..."
    env -u HTTP_PROXY -u HTTPS_PROXY -u http_proxy -u https_proxy \
        nohup ./cloudflared-linux tunnel \
        --url "127.0.0.1:$ECHPORT" \
        --metrics "127.0.0.1:$ARGO_PORT" \
        $ARGO_ARGS >"$CLOUDFLARED_LOG" 2>&1 &

    sleep 3

    # ================= 获取域名 =================
    if [ -n "$ARGO_DOMAIN" ]; then
        TUNNEL_DOMAIN="$ARGO_DOMAIN"
    else
        for i in $(seq 1 30); do
            TUNNEL_DOMAIN=$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' "$CLOUDFLARED_LOG" | head -n 1)
            [ -n "$TUNNEL_DOMAIN" ] && break
            TUNNEL_DOMAIN=$(curl -s --connect-timeout 2 --max-time 3 \
                "http://127.0.0.1:$ARGO_PORT/metrics" \
                | grep 'userHostname=' \
                | sed -E 's/.*userHostname="([^"]+)".*/\1/')
            [ -n "$TUNNEL_DOMAIN" ] && break
            sleep 1
        done
    fi

    if [ -z "$TUNNEL_DOMAIN" ]; then
        echo "⚠️  获取隧道域名失败，Node.js 服务仍在运行"
        return 0
    fi

    echo "✓ 隧道域名: $TUNNEL_DOMAIN"

    # ================= 写入页面 =================
    cat > ./tunnel_index.html <<EOF
<!DOCTYPE html>
<html lang="zh-CN">
<head>
<meta charset="UTF-8">
<title>Tunnel Ready</title>
</head>
<body style="background:#020617;color:#e5e7eb;display:flex;align-items:center;justify-content:center;height:100vh">
<div>
<h1>🚀 Tunnel 已就绪</h1>
<p>$TUNNEL_DOMAIN</p>
</div>
</body>
</html>
EOF
}

# ================= main =================
# 清除旧的隧道页面，避免显示过期域名
rm -f ./tunnel_index.html

# 后台运行隧道设置
setup_tunnel &

# 立即启动 Node.js（保证健康检查通过）
echo "--- 启动 Node.js 服务器 ---"
# 使用 pwd 获取当前工作目录（兼容 dash/sh）
exec node "$(pwd)/server.js"
