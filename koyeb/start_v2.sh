#!/bin/sh



# 从环境变量中获取 CLOUDFLARED_TOKEN，如果没有则退出脚本
: "${CLOUDFLARED_TOKEN:?missing CLOUDFLARED_TOKEN}"

# 16个默认uuid列
uuid0="00000000-0000-0000-0000-000000000000"
uuid1="11111111-1111-1111-1111-111111111111"
uuid2="22222222-2222-2222-2222-222222222222"
uuid3="33333333-3333-3333-3333-333333333333"
uuid4="44444444-4444-4444-4444-444444444444"
uuid5="55555555-5555-5555-5555-555555555555"
uuid6="66666666-6666-6666-6666-666666666666"
uuid7="77777777-7777-7777-7777-777777777777"
uuid8="88888888-8888-8888-8888-888888888888"
uuid9="99999999-9999-9999-9999-999999999999"
uuida="aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
uuidb="bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
uuidc="cccccccc-cccc-cccc-cccc-cccccccccccc"
uuidd="dddddddd-dddd-dddd-dddd-dddddddddddd"
uuide="eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee"
uuidf="ffffffff-ffff-ffff-ffff-ffffffffffff"

# # xray vless enc设定
# decryption="mlkem768x25519plus.native.600s.YpQG-Oct_pBDuMd0HvPhMaH_JMsq1qJjkLEHyDaGuu9sy3kIe5EOKIZPrGahoqLtTRdCZRXWM8RkxMTqLP2Obw"
# encryption="mlkem768x25519plus.native.0rtt.yxqHhit6BVJpAHcvHisZ7DG8ctVXLPSFiotDrxmK18acqOYn4Mk8xZi4iqFnhQFLxUME-ZoMe9dc2LZW9nahmrvIu2xYAya5ZgYrgCox-LhIC6OZeym1FWitQ9NIz8MkPYoYTrMaXlKGozfLInknX7E4vPyRrhR7S2Gul4kuT6aUj2JiSSJZPVAtXGuwexA0cNjOUqF6Z7AYNSkojcF2aSJxm5hoaAFRIbEQqvqy5iib8FJRyCvHNqAFnVjFPzo8ZjMaNCgdoWTOUPkbsUaYlqewwJSUfAOneOwOxpcuRAIZKGZkYQLKtfHNUKknSAWKD9FdAgKUxVE8vKuzSRTKnMW2MJIkFNepeNWvwnQq2inF7_O0-nyq7KR1nVVv29ShM-w9UEWFOTBoD7AY8INlLtaddskjl_ci6odvJCalyueuAGlwZTmqjBicl9BNMJgCI2JSbKV9CpaTXXuZLnaLO0xHNZe20IkhcCiIsRAi-1JctKUXXtwoFDCd6HwRmutFsSgkStCwjvpDMSo7Jrksvqp9I_R1CQgf0ACBkhDAiYYjeLmxidNSutAz3TBhQVI5xkS1dPya-SUg2GCGRwsTxZzDlUeksEyW64kN9FOoTwYPNKeST5NJyPEOS0S_UPu7HDwOmkC4_VdOu_NhgbcfUCbC56tsUyuJSTq_PuQJhexIItiod1mhWPBNd1miKzpWXBgAF_Jx1uoGr3CANoefxZepTGssNoKwClgTQlihmbI_7Qt72rdjvWEkVZYw89rEq3d1dYBQ4RuMMspOk-dyaekyBLB3uhEATdZSONIz1Tq1zPYYQ5w92MmH68QL96uuUKLOI0Cpvui_r3cF5SQVwsqjJNnHG_lVtcuilUxoipsfPqGoZ3RP1ThfFZwU9KnPUkW5_kg0bjpYkkFmeDgXXBxntKCVOOFn0QufCfJQyXMxdykFDct_Vrsc_iAPPIOyDmZ4bNh9iuHID6C3I1touXd2jEN3JugCvPLD2yGIAxeemDFaEWuDy3MDdthyQHxKgPmyziMulXug1-mWzihRL6GUsaLA3ffMJ4UPH3y3y9wzXSGnnpSIFPvO3YmL4bAV4ETEtuWnM3J-rGsMOCG36BhfRQVvlTBxqyFRFgzLMlGi5LY2plxV1spUaNsc0aaGCwwvTpp67tCaz7KEOniCFcA8LzZP7ummtdMohxq2N3Rty5dL14SC91i9ZQg7_wijylSTT3zFyWZONLF-Nve3eoO35VZsM2PEjmN2EtCYPYkXB8JW26GOJCVBihtTiIN4dxAcWRJWciNzTMMIxecJnDZ271VLFPJHMMMG1XbDIBvIFOIqy1g-CiRtBmFujPQWvOHPGrtHuSN5iPG3eSCM20NeM_ymWflkCuVz6MQ4YaRPS8IqwtB1kIBUDYJUxxC93spp-NB1TJlvzaLOYshoHqJuSUSx8akMAciG1SbDelhWLaWuN7LCxmtn8PJ3ooqX-iSjwyrJsftMBDoka4sI_CCINAIHWlwlsapr1dFVGYcwzddSFxgNFOyRmeIOmBkPnoN65ADF6ACDC0AbTxNhYepTmsM-Wxc2yM67bhLbVf4"





# ========== 安装curl jq unzip nginx wireguard-tools ca-certificates
echo "安装curl jq unzip nginx wireguard-tools ca-certificates"

apk add --no-cache curl jq unzip nginx wireguard-tools ca-certificates
update-ca-certificates





# ========== 安装xray
echo "安装xray"

mkdir /xray
mkdir -p /etc/xray

XRAY_api=$(curl -fsSL https://api.github.com/repos/XTLS/xray-core/releases?per_page=1)
XRAY_url=$(echo "${XRAY_api}" | jq -r '.[0].assets[] | select(.name | endswith("linux-64.zip")) | .browser_download_url')

curl -fsSL "${XRAY_url}" -o /xray/xray.zip
unzip /xray/xray.zip -d /xray

mv /xray/xray /usr/local/bin/xray
chmod +x /usr/local/bin/xray

rm -rf /xray





# ========== warp-reg.sh for apline
echo "warp-reg.sh注册warp"

API_URL="${API_URL:-https://api.cloudflareclient.com/v0a2158/reg}"
CF_CLIENT_VERSION="${CF_CLIENT_VERSION:-a-7.21-0721}"
MTU="${MTU:-1280}"

err() {
    printf >&2 'ERROR: %s\n' "$*"
    exit 1
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || err "missing command: $1"
}

check_deps() {
    need_cmd curl
    need_cmd jq
    need_cmd wg
    need_cmd base64
    need_cmd od
    need_cmd date
    need_cmd mktemp
}

utc_now() {
    date -u '+%Y-%m-%dT%H:%M:%S.000Z'
}

gen_keys() {
    private_key=$(wg genkey) || err 'failed to generate WireGuard private key'
    public_key_client=$(printf '%s' "$private_key" | wg pubkey) || err 'failed to derive WireGuard public key'
}

register_warp() {
    tmp_json=$(mktemp)
    trap 'rm -f "$tmp_json"' EXIT INT TERM

    payload=$(jq -cn \
        --arg key "$public_key_client" \
        --arg tos "$(utc_now)" \
        '{key:$key,tos:$tos}'
    ) || err 'failed to build registration payload'

    curl -fsSL --tlsv1.3 -X POST "$API_URL" \
        -H "CF-Client-Version: $CF_CLIENT_VERSION" \
        -H 'Content-Type: application/json' \
        --data "$payload" \
        -o "$tmp_json" \
        || err 'Cloudflare WARP registration request failed'

    jq -e '
        (.config.client_id // "" | length > 0) and
        (.config.peers[0].public_key // "" | length > 0) and
        (.config.peers[0].endpoint.v4 // "" | length > 0) and
        (.config.interface.addresses.v4 // "" | length > 0)
    ' "$tmp_json" >/dev/null || {
        cat "$tmp_json" >&2
        err 'unexpected WARP registration response'
    }
}

make_reserved() {
    client_id=$(jq -r '.config.client_id' "$tmp_json")

    reserved_hex=$(printf '%s' "$client_id" | base64 -d | od -An -tx1 -v | tr -d ' \n') \
        || err 'failed to decode client_id as hex'

    reserved_dec_csv=$(printf '%s' "$client_id" | base64 -d | od -An -tu1 -v | tr -s ' ' '\n' | awk 'NF { printf "%s%s", sep, $1; sep=", " }') \
        || err 'failed to decode client_id as decimal bytes'

    [ -n "$reserved_hex" ] || err 'empty reserved_hex decoded from client_id'
    [ -n "$reserved_dec_csv" ] || err 'empty reserved_dec decoded from client_id'
}

assign_warp_vars() {
    # 依赖：
    # 1. private_key 已经由 gen_keys() 生成
    # 2. tmp_json 是 Cloudflare WARP 注册接口返回内容的临时 JSON 文件
    # 3. jq 已安装
    # 4. base64 / od / awk 可用；Alpine BusyBox 默认通常有
    # 5. MTU 可选，默认 1280

    public_key=$(jq -r '.config.peers[0].public_key // empty' "$tmp_json")

    address_v4=$(jq -r '.config.interface.addresses.v4 // empty' "$tmp_json")
    address_v6=$(jq -r '.config.interface.addresses.v6 // empty' "$tmp_json")

    addresses=$(jq -rn \
        --arg v4 "$address_v4" \
        --arg v6 "$address_v6" '
        [
            if $v4 != "" then $v4 + "/32" else empty end,
            if $v6 != "" then $v6 + "/128" else empty end
        ]
        | map(@json)
        | join(", ")
    ')

    allowed_ips=$(jq -rn '
        ["0.0.0.0/0", "::/0"]
        | map(@json)
        | join(", ")
    ')

    reserved_str=$(jq -r '.config.client_id // empty' "$tmp_json")

    reserved=$(printf '%s' "$reserved_str" \
        | base64 -d 2>/dev/null \
        | od -An -tu1 -v \
        | awk '
            NF {
                for (i = 1; i <= NF; i++) {
                    printf "%s%s", sep, $i
                    sep = ", "
                }
            }
        '
    )

    mtu="${MTU:-1280}"

}

main() {
    check_deps
    gen_keys
    register_warp
    make_reserved
    assign_warp_vars
}

main "$@"





# ========== 写入xray
echo "写入xray"

mkdir -p /etc/xray/confs

if [ -z "$private_key" ] || \
    [ -z "$addresses" ] || \
    [ -z "$public_key" ] || \
    [ -z "$allowed_ips" ] || \
    [ -z "$reserved" ] || \
    [ -z "$mtu" ]; then
    echo "注册warp 失败"

# 出站文件
cat <<EOF > /etc/xray/confs/outbounds.json
{
    "outbounds": [
        {
            "tag": "direct",
            "protocol": "freedom"
        }
    ]
}
EOF

else
    echo "注册warp 成功"

# 路由文件
cat <<EOF > /etc/xray/confs/routing.json
{
    "routing": {
        "rules": [
            {
                "inboundTag": ["vless_ws_cf","vless_xhttp_cf"],
                "outboundTag": "wg"
            }
        ]
    }
}
EOF

# wg出站文件
cat <<EOF > /etc/xray/confs/outbounds.json
{
    "outbounds": [
        {
            "tag": "direct",
            "protocol": "freedom"
        },
        {  
            "tag": "wg",
            "protocol": "wireguard",
            "settings": {
                "secretKey": "$private_key",
                "address": [ $addresses ],
                "peers": [
                    {
                    "publicKey": "$public_key",
                    "allowedIPs": [ $allowed_ips ],
                    "endpoint": "162.159.192.1:2408"
                    }
                ],
            "reserved": [ $reserved ],
            "mtu": $mtu
            }
        }
    ]
}
EOF

fi

# 入站文件
cat <<EOF > /etc/xray/confs/inbounds.json
{
    "inbounds": [
        {
            "tag": "vless_ws",
            "listen": "127.0.0.1",
            "port": 11111,
            "protocol": "vless",
            "settings": {
                "decryption": "none",
                "clients": [
                    {
                        "id": "$uuid0"
                    },
                    {
                        "id": "$uuid1"
                    },
                    {
                        "id": "$uuid2"
                    },
                    {
                        "id": "$uuid3"
                    },
                    {
                        "id": "$uuid4"
                    },
                    {
                        "id": "$uuid5"
                    },
                    {
                        "id": "$uuid6"
                    },
                    {
                        "id": "$uuid7"
                    },
                    {
                        "id": "$uuid8"
                    },
                    {
                        "id": "$uuid9"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/ws"
                }
            }
        },
        {
            "tag": "vless_ws_cf",
            "listen": "127.0.0.1",
            "port": 22222,
            "protocol": "vless",
            "settings": {
                "decryption": "none",
                "clients": [
                    {
                        "id": "$uuid0"
                    },
                    {
                        "id": "$uuid1"
                    },
                    {
                        "id": "$uuid2"
                    },
                    {
                        "id": "$uuid3"
                    },
                    {
                        "id": "$uuid4"
                    },
                    {
                        "id": "$uuid5"
                    },
                    {
                        "id": "$uuid6"
                    },
                    {
                        "id": "$uuid7"
                    },
                    {
                        "id": "$uuid8"
                    },
                    {
                        "id": "$uuid9"
                    }
                ]
            },
            "streamSettings": {
                "network": "ws",
                "wsSettings": {
                    "path": "/ws2cf"
                }
            }
        },
        {
            "tag": "vless_xhttp",
            "listen": "127.0.0.1",
            "port": 33333,
            "protocol": "vless",
            "settings": {
                "decryption": "none",
                "clients": [
                    {
                        "id": "$uuida"
                    },
                    {
                        "id": "$uuidb"
                    },
                    {
                        "id": "$uuidc"
                    },
                    {
                        "id": "$uuidd"
                    },
                    {
                        "id": "$uuide"
                    },
                    {
                        "id": "$uuidf"
                    }
                ]
            },
            "streamSettings": {
                "network": "xhttp",
                "xhttpSettings": {
                    "path": "/xhttp",
                    "mode": "auto"
                }
            }
        },
        {
            "tag": "vless_xhttp_cf",
            "listen": "127.0.0.1",
            "port": 44444,
            "protocol": "vless",
            "settings": {
                "decryption": "none",
                "clients": [
                    {
                        "id": "$uuida"
                    },
                    {
                        "id": "$uuidb"
                    },
                    {
                        "id": "$uuidc"
                    },
                    {
                        "id": "$uuidd"
                    },
                    {
                        "id": "$uuide"
                    },
                    {
                        "id": "$uuidf"
                    }
                ]
            },
            "streamSettings": {
                "network": "xhttp",
                "xhttpSettings": {
                    "path": "/xhttp2cf",
                    "mode": "auto"
                }
            }
        }
    ]
}
EOF

# log文件
cat <<EOF > /etc/xray/confs/log.json
{
    "log": {
        "loglevel": "error"
    }
}
EOF




# ========== 安装cfd
echo "安装cfd"
curl -fsSL https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared





# ========== Docker Hub 反代
echo "写入 docker registry 反代 nginx 配置"

mkdir -p /run/nginx /var/lib/nginx/tmp/client_body

cat <<'EOF' > /etc/nginx/nginx.conf

user nginx;
worker_processes auto;
pid /run/nginx/nginx.pid;

events {
    worker_connections 1024;
}

http {
    include /etc/nginx/mime.types;
    default_type application/octet-stream;

    server_tokens off;

    access_log off;
    error_log /dev/stderr warn;

    # 动态 Docker CDN 域名解析
    resolver 1.1.1.1 8.8.8.8 ipv6=off valid=300s;
    resolver_timeout 5s;

    sendfile on;
    tcp_nopush on;

    keepalive_timeout 65s;

    # Docker 镜像及 XHTTP 不限制请求体大小
    client_max_body_size 0;
    client_body_timeout 3600s;
    send_timeout 3600s;

    # 通用反向代理设置
    proxy_ssl_server_name on;
    proxy_http_version 1.1;

    proxy_buffering off;
    proxy_request_buffering off;

    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;

    # WebSocket Connection 头
    map $http_upgrade $connection_upgrade {
        default upgrade;
        ''      close;
    }

    # 重写 Docker Registry 返回的认证地址
    map $upstream_http_www_authenticate $docker_auth_header {
        default $upstream_http_www_authenticate;

        "~Bearer realm=\"https://auth\.docker\.io/token\",(.*)"
        "Bearer realm=\"https://$http_host/token\",$1";
    }

    server {
        # Koyeb 当前唯一公开的容器端口
        listen 0.0.0.0:55555 default_server;

        server_name _;

        # =========================================================
        # 基础响应
        # =========================================================

        # Koyeb 健康检查
        location = /healthz {
            access_log off;
            default_type text/plain;
            return 200 "ok\n";
        }

        # 根路径返回正常响应
        location = / {
            access_log off;
            default_type text/plain;
            return 200 "ok\n";
        }


        # =========================================================
        # Xray WebSocket
        # =========================================================

        # Koyeb 主路线：
        # /ws -> Xray 127.0.0.1:11111
        location = /ws {
            proxy_pass http://127.0.0.1:11111;

            proxy_http_version 1.1;

            proxy_set_header Host $http_host;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;

            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            proxy_buffering off;
            proxy_request_buffering off;

            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }

        # Cloudflared 备选路线：
        # /ws2cf -> Xray 127.0.0.1:22222
        location = /ws2cf {
            proxy_pass http://127.0.0.1:22222;

            proxy_http_version 1.1;

            proxy_set_header Host $http_host;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection $connection_upgrade;

            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            proxy_buffering off;
            proxy_request_buffering off;

            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;
        }


        # =========================================================
        # Xray XHTTP
        # =========================================================

        # 注意：
        # XHTTP 实际请求不只有 /xhttp，
        # 还会出现：
        #
        # /xhttp/<session-id>
        # /xhttp/<session-id>/<sequence>
        #
        # 所以不能使用：
        #
        # location = /xhttp
        #
        # 必须匹配 /xhttp 及其所有子路径。

        # Koyeb 主路线：
        # /xhttp/... -> Xray 127.0.0.1:33333
        location ~ ^/xhttp(?:/|$) {
            proxy_pass http://127.0.0.1:33333;

            proxy_http_version 1.1;

            proxy_set_header Host $http_host;

            # XHTTP 不是 WebSocket，不传 Upgrade
            proxy_set_header Connection "";

            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            # 禁止缓存和请求缓冲，确保流式传输
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_cache off;

            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;

            add_header X-Accel-Buffering no always;
        }

        # Cloudflared 备选路线：
        # /xhttp2cf/... -> Xray 127.0.0.1:44444
        location ~ ^/xhttp2cf(?:/|$) {
            proxy_pass http://127.0.0.1:44444;

            proxy_http_version 1.1;

            proxy_set_header Host $http_host;
            proxy_set_header Connection "";

            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;

            proxy_buffering off;
            proxy_request_buffering off;
            proxy_cache off;

            proxy_read_timeout 3600s;
            proxy_send_timeout 3600s;

            add_header X-Accel-Buffering no always;
        }


        # =========================================================
        # Docker Hub Token Service
        # =========================================================

        location = /token {
            # 使用变量延迟 DNS 解析，避免 Nginx 启动时
            # 因临时 DNS 失败而整个启动失败
            set $docker_auth_upstream auth.docker.io;

            proxy_pass https://$docker_auth_upstream/token$is_args$args;

            proxy_ssl_name $docker_auth_upstream;
            proxy_ssl_server_name on;

            proxy_set_header Host auth.docker.io;
            proxy_set_header User-Agent $http_user_agent;
        }


        # =========================================================
        # Docker Registry V2 API
        # =========================================================

        location /v2/ {
            set $docker_registry_upstream registry-1.docker.io;

            # 保留原始 /v2/... 请求路径及查询参数
            proxy_pass https://$docker_registry_upstream$request_uri;

            proxy_ssl_name $docker_registry_upstream;
            proxy_ssl_server_name on;

            proxy_set_header Host registry-1.docker.io;
            proxy_set_header Authorization $http_authorization;
            proxy_set_header User-Agent $http_user_agent;

            proxy_hide_header WWW-Authenticate;

            add_header WWW-Authenticate
                $docker_auth_header
                always;

            add_header Docker-Distribution-Api-Version
                registry/2.0
                always;

            # Docker Hub 返回 Blob CDN 地址时，
            # 将跳转地址重写回当前反代域名
            proxy_redirect
                ~^https://([^/]+)/(.*)$
                https://$http_host/proxy/$1/$2;
        }


        # =========================================================
        # Docker Blob CDN
        # =========================================================

        # 处理经过上面重写后的：
        #
        # /proxy/<上游域名>/<文件路径>
        location ~ ^/proxy/([^/]+)(/.*)$ {
            proxy_pass https://$1$2$is_args$args;

            proxy_ssl_name $1;
            proxy_ssl_server_name on;

            proxy_set_header Host $1;

            # Blob CDN 一般不需要 Docker Authorization
            proxy_set_header Authorization "";
            proxy_set_header User-Agent $http_user_agent;

            proxy_redirect
                ~^https://([^/]+)/(.*)$
                https://$http_host/proxy/$1/$2;
        }


        # =========================================================
        # 其他路径
        # =========================================================

        location / {
            return 404;
        }
    }
}

EOF





# ========== 定时任务写入 /etc/crontabs/root
cat <<EOF > /etc/crontabs/root

*/5 * * * pgrep -x "/usr/local/bin/xray" > /dev/null || nohup /usr/local/bin/xray run -confdir /etc/xray/confs/ > /dev/null 2>&1 &

*/5 * * * pgrep -x "/usr/local/bin/cloudflared" > /dev/null || nohup /usr/local/bin/cloudflared tunnel --loglevel fatal run --token $CLOUDFLARED_TOKEN > /dev/null 2>&1 &

*/5 * * * pgrep -f "nginx: master process" > /dev/null || nginx -c /etc/nginx/nginx.conf

*/15 * * * curl -fsSL --max-time 20 "https://$KOYEB_PUBLIC_DOMAIN/v2/" > keep_alive.log

EOF





# ========== 启动
# 清理
apk del jq unzip wireguard-tools
apk cache clean

echo "后台启动cloudflared"
nohup /usr/local/bin/cloudflared tunnel --loglevel fatal run --token "$CLOUDFLARED_TOKEN" > /dev/null 2>&1 &

echo "后台启动xray"
nohup /usr/local/bin/xray run -confdir /etc/xray/confs/ > /dev/null 2>&1 &

echo "后台启动nginx docker registry proxy"
nginx -c /etc/nginx/nginx.conf

echo "前台启动crond保活容器"
crond -f
