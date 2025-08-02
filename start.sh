#!/bin/sh



# CLOUDFLARED_TOKEN=""

# 如果UUID1, UUID2, UUID3, UUID4, UUID5未设置，则使用默认值
if [ -z "$UUID1" ]; then
    echo "UUID1未设置，使用默认值"
    UUID1="11111111-1111-1111-1111-111111111111"
fi
if [ -z "$UUID2" ]; then
    echo "UUID2未设置，使用默认值"
    UUID2="22222222-2222-2222-2222-222222222222"
fi
if [ -z "$UUID3" ]; then
    echo "UUID3未设置，使用默认值"
    UUID3="33333333-3333-3333-3333-333333333333"
fi
if [ -z "$UUID4" ]; then
    echo "UUID4未设置，使用默认值"
    UUID4="44444444-4444-4444-4444-444444444444"
fi
if [ -z "$UUID5" ]; then
    echo "UUID5未设置，使用默认值"
    UUID5="55555555-5555-5555-5555-555555555555"
fi



# 安装curl jq unzip
echo "安装curl jq unzip"
apk add curl jq unzip



# 安装sing-box
echo "安装sing-box"
mkdir /sing-box
mkdir -p /etc/sing-box
SB_api=$(curl -fsSL https://api.github.com/repos/SagerNet/sing-box/releases/latest)
SB_url=$(echo "${SB_api}" | jq -r '.assets[] | select(.name | endswith("linux-amd64.tar.gz")) | .browser_download_url')
SB_name=$(echo "${SB_api}" | jq -r '.assets[] | select(.name | endswith("linux-amd64.tar.gz")) | .name' | sed 's/\.tar\.gz$//')
curl -fsSL "${SB_url}" | tar -zxvf - -C /sing-box
mv /sing-box/${SB_name}/sing-box /usr/local/bin/sing-box
chmod +x /usr/local/bin/sing-box
rm -rf /sing-box



# 写入sing-box配置
cat <<EOF > /etc/sing-box/config.json
{
    "log": {
        "level": "fatal"
    },
    "inbounds": [
        {
            "type": "vless",
            "listen": "0.0.0.0",
            "listen_port": 22222,
            "users": [
                { "uuid": "$UUID1" },
                { "uuid": "$UUID2" },
                { "uuid": "$UUID3" },
                { "uuid": "$UUID4" },
                { "uuid": "$UUID5" }
            ],
            "transport": {
                "type": "ws",
                "path": "/ws",
                "max_early_data": 2560,
                "early_data_header_name": "Sec-WebSocket-Protocol"
            },
            "multiplex": {
                "enabled": true,
                "padding": true
            }
        }
    ],
    "outbounds": [
        {
            "type": "direct"
        }
    ]
}
EOF



# echo "安装xray"
# # curl -L https://github.com/XTLS/Xray-install/raw/main/alpinelinux/install-release.sh | ash
# mkdir /xray
# mkdir -p /etc/xray
# XRAY_api=$(curl -fsSL https://api.github.com/repos/XTLS/xray-core/releases/latest)
# XRAY_url=$(echo "${XRAY_api}" | jq -r '.assets[] | select(.name | endswith("linux-64.zip")) | .browser_download_url')
# # XRAY_name=$(echo "${XRAY_api}" | jq -r '.assets[] | select(.name | endswith("linux-64.zip")) | .name' | sed 's/\.zip$//')
# curl -fsSL "${XRAY_url}" -o /xray/xray.zip
# unzip /xray/xray.zip -d /xray
# mv /xray/xray /usr/local/bin/xray
# chmod +x /usr/local/bin/xray
# rm -rf /xray



# 环境变量中CLOUDFLARED_TOKEN有设置的话，则安装cfd
if [ -z "$CLOUDFLARED_TOKEN" ]; then
    
    echo "CLOUDFLARED_TOKEN未设置，跳过cfd安装"
    
    # 清理curl jq unzip
    apk del curl jq unzip
    
    echo "前台启动sing-box"
    /usr/local/bin/sing-box run -c /etc/sing-box/config.json
    
else
    
    echo "安装cfd"
    curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
    chmod +x /usr/local/bin/cloudflared
    
    # 清理curl jq unzip
    apk del curl jq unzip
    
    echo "后台启动sing-box"
    nohup /usr/local/bin/sing-box run -c /etc/sing-box/config.json &
    
    echo "前台启动cloudflared"
    /usr/local/bin/cloudflared tunnel --no-autoupdate --protocol http2 --loglevel fatal run --token $CLOUDFLARED_TOKEN
    
fi




