#!/bin/sh

# 从环境变量中获取 CLOUDFLARED_TOKEN，如果没有则退出脚本
: "${CLOUDFLARED_TOKEN:?missing CLOUDFLARED_TOKEN}"
: "${REALM_TOKEN:?missing REALM_TOKEN}"


# ============================================================
# [网络性能优化] Go 并行度
#
# Koyeb Free 只有 0.1 vCPU。
# cloudflared 和 Xray 都是 Go 程序。
#
# 即使新版 Go 已经能识别 cgroup CPU quota，
# Go 当前对自动 GOMAXPROCS 仍有最小 2 的规则。
# 对只有 0.1 vCPU 的实例，2 个并行执行线程仍明显高于实际 CPU 配额，
# 容易产生短时 CPU burst -> cgroup throttling。
#
# 固定 GOMAXPROCS=1：
# - 不限制 goroutine 数量
# - 不妨碍异步网络 I/O
# - 只限制同时执行 Go 代码的并行度
# - 减少 cloudflared / Xray 内部 CPU 调度竞争和 quota throttling
#
# 如果外部已经显式指定 GOMAXPROCS，则尊重外部值。
# ============================================================
export GOMAXPROCS="${GOMAXPROCS:-1}"


# ============================================================
# [新增] 网络性能优化：仅调整 Linux TCP/UDP 参数
#
# 当前 Koyeb Free：0.1 vCPU / 512 MB RAM。
# 原则：QUIC/UDP 给足必要缓冲；TCP 保留自动调优；不盲目放大队列和内存。
# 所有设置都 best-effort：容器无权限、内核不支持时直接跳过，不影响后续启动。
# ============================================================
echo "尝试 TCP / UDP 网络性能优化"

net_log() {
    echo "[NET] $*"
}

# 尝试写入 sysctl；失败只记录，不中断脚本。
try_sysctl() {
    key="$1"
    value="$2"
    old="$(sysctl -n "$key" 2> /dev/null || true)"

    if [ -z "$old" ]; then
        net_log "SKIP $key（参数不存在或当前容器不可见）"
        return 0
    fi

    if sysctl -w "$key=$value" > /dev/null 2>&1; then
        net_log "OK   $key: $old -> $(sysctl -n "$key" 2> /dev/null || true)"
    else
        net_log "FAIL $key=$value（权限不足 / 内核限制 / 容器限制）"
    fi
    return 0
}

# 单值整数参数只提高、不降低；便于以后复用到配置更高的 Docker/VPS。
ensure_min_sysctl() {
    key="$1"
    target="$2"
    current="$(sysctl -n "$key" 2> /dev/null || true)"

    case "$current" in
        '' | *[!0-9]*)
            net_log "SKIP $key（不存在或无法解析：${current:-N/A}）"
            return 0
            ;;
    esac

    if [ "$current" -lt "$target" ]; then
        try_sysctl "$key" "$target"
    else
        net_log "KEEP $key=$current"
    fi
}

# tcp_rmem/tcp_wmem = min default max；只提高第三个 max。
# 8 MiB 只是自动调节允许达到的上限，不会给每条连接预分配 8 MiB。
ensure_tcp_buffer_max() {
    key="$1"
    target="$2"
    old="$(sysctl -n "$key" 2> /dev/null || true)"
    set -- $old

    if [ "$#" -lt 3 ]; then
        net_log "SKIP $key（不存在或无法解析：${old:-N/A}）"
        return 0
    fi

    min="$1"
    def="$2"
    max="$3"
    case "$max" in
        *[!0-9]*)
            net_log "SKIP $key（无法解析：$old）"
            return 0
            ;;
    esac

    if [ "$max" -lt "$target" ]; then
        try_sysctl "$key" "$min $def $target"
    else
        net_log "KEEP $key=$old"
    fi
}

network_tune() {
    # 1) QUIC / UDP：cloudflared QUIC 最直接相关。
    # quic-go 会主动申请更大的 UDP socket buffer，但受这两个系统上限约束。
    # 7340032 bytes ≈ 7 MiB；这里只提高“可申请上限”，不是固定占用。
    ensure_min_sysctl net.core.rmem_max 7340032
    ensure_min_sysctl net.core.wmem_max 7340032

    # 2) TCP：Xray direct TCP / Nginx TCP 使用 Linux TCP 栈。
    # 保持自动接收窗口和 Window Scaling；最大自动窗口只保证到 8 MiB。
    # 对 0.1 vCPU 已足够，不使用 16/32/64 MiB 的激进值。
    try_sysctl net.ipv4.tcp_moderate_rcvbuf 1
    try_sysctl net.ipv4.tcp_window_scaling 1
    ensure_tcp_buffer_max net.ipv4.tcp_rmem 8388608
    ensure_tcp_buffer_max net.ipv4.tcp_wmem 8388608

    # 3) TCP PMTU black-hole 探测。
    # 云网络若错误丢弃 ICMP Packet Too Big，可能出现“小包正常、大包卡住”。
    # 设为 1 仅在检测到异常时启动探测；QUIC 自己有独立的路径 MTU 机制。
    try_sysctl net.ipv4.tcp_mtu_probing 1

    # 4) SACK：丢包时只重传真正缺失的数据段，现代 Linux 通常默认已开启。
    try_sysctl net.ipv4.tcp_sack 1

    # 5) Listener 队列只保证到 1024。
    # 0.1 vCPU 的瓶颈是处理能力，不是排队容量；队列过大只会增加延迟和内存压力。
    ensure_min_sysctl net.core.somaxconn 1024
    ensure_min_sysctl net.ipv4.tcp_max_syn_backlog 1024
    try_sysctl net.ipv4.tcp_syncookies 1

    # 6) BBR：只有内核已经提供时才尝试，不加载模块。
    # 仅影响 TCP；cloudflared QUIC 和 Xray WireGuard/UDP 不使用 Linux TCP BBR。
    available_cc="$(sysctl -n net.ipv4.tcp_available_congestion_control 2> /dev/null || true)"
    case " $available_cc " in
        *" bbr "*) try_sysctl net.ipv4.tcp_congestion_control bbr ;;
        *) net_log "SKIP BBR（当前可用算法：${available_cc:-unknown}）" ;;
    esac

    # 刻意不改：tcp_no_metrics_save、tcp_slow_start_after_idle、tcp_keepalive_*、
    # udp_mem/tcp_mem、netdev_max_backlog、tcp_tw_reuse、fin_timeout/retries。
    # 原因：这些要么不是通用增益，要么会增加 0.1 vCPU/512 MB 下的排队/定时器压力，
    # 要么会改变连接生命周期和失败判定，不适合作为“无副作用的一键优化”。

    # 只读取 UDP 错误计数，方便以后判断是否真的出现 socket buffer/CPU 丢包。
    if [ -r /proc/net/snmp ]; then
        grep '^Udp:' /proc/net/snmp 2> /dev/null || true
    fi

    # 7) 文件描述符上限
    #
    # socket 本质也是文件描述符。
    # Nginx、Xray、cloudflared、realm 都会继承当前 shell 的 soft limit。
    # 对 0.1 vCPU 不需要设置十万甚至百万级；
    # 4096 已经远高于实际可持续连接规模。
    current_nofile="$(ulimit -n 2> /dev/null || true)"

    case "$current_nofile" in
        '' | unlimited) ;;
        *[!0-9]*) ;;
        *)
            if [ "$current_nofile" -lt 4096 ]; then
                if ulimit -n 4096 2> /dev/null; then
                    net_log "OK   NOFILE: $current_nofile -> $(ulimit -n)"
                else
                    net_log "FAIL NOFILE -> 4096（容器 hard limit 不允许）"
                fi
            else
                net_log "KEEP NOFILE=$current_nofile"
            fi
            ;;
    esac

    net_log "网络性能优化尝试完成"
    return 0
}

if command -v sysctl > /dev/null 2>&1; then
    network_tune || true
else
    net_log "SKIP：当前容器没有 sysctl 命令"
fi
# ====================== [新增网络优化结束] ======================

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
MTU="${MTU:-1420}"

err() {
    printf >&2 'ERROR: %s\n' "$*"
    exit 1
}

need_cmd() {
    command -v "$1" > /dev/null 2>&1 || err "missing command: $1"
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

    payload=$(
        jq -cn \
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
    ' "$tmp_json" > /dev/null || {
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
    # 5. MTU 可选，默认 1420

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

    reserved=$(
        printf '%s' "$reserved_str" \
            | base64 -d 2> /dev/null \
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

    mtu="$MTU"

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

if [ -z "$private_key" ] \
    || [ -z "$addresses" ] \
    || [ -z "$public_key" ] \
    || [ -z "$allowed_ips" ] \
    || [ -z "$reserved" ] \
    || [ -z "$mtu" ]; then
    echo "注册warp 失败"

    # 出站文件
    cat << EOF > /etc/xray/confs/outbounds.json
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
    cat << EOF > /etc/xray/confs/routing.json
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
    cat << EOF > /etc/xray/confs/outbounds.json
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
cat << EOF > /etc/xray/confs/inbounds.json
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
cat << EOF > /etc/xray/confs/log.json
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

# ========= 安装REALM
REALM_api=$(curl -fsSL https://api.github.com/repos/apernet/hysteria-realm-server/releases?per_page=1)
REALM_url=$(echo "${REALM_api}" | jq -r '.[0].assets[] | select(.name | endswith("linux-amd64")) | .browser_download_url')
curl -fsSL "${REALM_url}" -o /usr/local/bin/realm
chmod +x /usr/local/bin/realm

# ========== Docker Hub 反代
echo "写入 docker registry 反代 nginx 配置"

mkdir -p /run/nginx /var/lib/nginx/tmp/client_body

cat << 'EOF' > /etc/nginx/nginx.conf

user nginx;

# [网络性能优化]
# Koyeb Free 只有 0.1 vCPU，而且同容器还有 cloudflared / Xray / WG。
# worker_processes auto 在容器环境中可能按宿主机可见 CPU 数量生成多个 worker，
# 多 worker 无法获得更多 CPU quota，只会增加调度和内存开销。
# 因此固定为 1 个 worker。
worker_processes 1;

pid /run/nginx/nginx.pid;

events {
    # [网络性能优化]
    # worker_connections 包含客户端连接和 upstream 连接，
    # 反向代理一次连接通常会同时占 client + upstream 两个连接。
    #
    # 1024 本身不会预分配 1024 个连接的全部资源，只是上限。
    # 对 0.1 vCPU 来说已经很充足，因此保持 1024，不需要继续放大。
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
cat << EOF > /etc/crontabs/root

*/5 * * * pgrep -f "nginx: master process" > /dev/null || nginx -c /etc/nginx/nginx.conf

*/5 * * * pgrep -x "/usr/local/bin/cloudflared" > /dev/null || nohup /usr/local/bin/cloudflared tunnel --edge-ip-version auto --protocol quic --loglevel fatal run --token "$CLOUDFLARED_TOKEN" > /dev/null 2>&1 &

*/5 * * * pgrep -x "/usr/local/bin/xray" > /dev/null || nohup /usr/local/bin/xray run -confdir /etc/xray/confs/ > /dev/null 2>&1 &

*/5 * * * pgrep -x "/usr/local/bin/realm" > /dev/null || /usr/local/bin/realm --token "$REALM_TOKEN" --listen 127.0.0.1:5555 > /dev/null 2>&1 &

*/15 * * * curl -fsSL --max-time 20 "https://$KOYEB_PUBLIC_DOMAIN/healthz" > keep_alive.log

EOF

# ========== 启动
# 清理
apk del jq unzip wireguard-tools
# apk cache clean

echo "后台启动nginx docker registry proxy"
nginx -c /etc/nginx/nginx.conf

echo "后台启动cloudflared"
nohup /usr/local/bin/cloudflared tunnel --edge-ip-version auto --protocol quic --loglevel fatal run --token "$CLOUDFLARED_TOKEN" > /dev/null 2>&1 &

echo "后台启动xray"
nohup /usr/local/bin/xray run -confdir /etc/xray/confs/ > /dev/null 2>&1 &

echo "后台启动realm"
nohup /usr/local/bin/realm --token "$REALM_TOKEN" --listen 127.0.0.1:5555 > /dev/null 2>&1 &

echo "前台启动crond保活容器"
crond -f
