#!/bin/bash
set -e

# ============================================
# Meilink frps 服务端一键部署脚本
# 在 VPS 上运行此脚本即可完成部署
# ============================================

# 配置区域
FRP_VERSION="v0.70.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/frps.toml"
COMMAND="${1:-deploy}"

usage() {
    cat <<EOF
用法:
  ./deploy-frps.sh [command]

命令:
  deploy    安装或更新 frps，并启动服务（默认）
  start     启动 frps 服务
  stop      停止 frps 服务
  restart   重启 frps 服务
  status    查看 frps 服务状态
  help      显示帮助
EOF
}

require_systemctl() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "当前系统未找到 systemctl，无法管理 frps 服务。"
        exit 1
    fi
}

require_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "找不到 frps 配置文件: $CONFIG_FILE"
        echo "请把 frps.toml 和 deploy-frps.sh 放在同一目录，并先修改其中的域名和 Token。"
        exit 1
    fi
}

get_toml_value() {
    local key="$1"
    awk -F= -v key="$key" '
        {
            left = $1
            gsub(/^[ \t]+|[ \t]+$/, "", left)
            if (left == key) {
                val = $0
                sub(/^[^=]*=/, "", val)
                gsub(/^[ \t]+|[ \t]+$/, "", val)
                gsub(/^"|"$/, "", val)
                print val
            }
        }
    ' "$CONFIG_FILE" | tail -n 1
}

FRPS_PORT=""
HTTP_PORT=""
HTTPS_PORT=""
SUB_DOMAIN_HOST=""

load_config_values() {
    FRPS_PORT="$(get_toml_value bindPort)"
    HTTP_PORT="$(get_toml_value vhostHTTPPort)"
    HTTPS_PORT="$(get_toml_value vhostHTTPSPort)"
    SUB_DOMAIN_HOST="$(get_toml_value subDomainHost)"
}

print_config_summary() {
    echo "=========================================="
    echo "  Meilink frps 服务端部署"
    echo "=========================================="
    echo ""
    echo "使用配置文件: $CONFIG_FILE"
    echo ""
    echo "配置信息:"
    echo "  - 客户端端口: ${FRPS_PORT:-未配置}"
    echo "  - HTTP 端口: ${HTTP_PORT:-未配置}"
    echo "  - HTTPS 端口: ${HTTPS_PORT:-未配置}"
    echo "  - 子域名基域: ${SUB_DOMAIN_HOST:-未配置}"
    echo ""
}

start_service() {
    require_systemctl
    echo "正在启动 frps..."
    sudo systemctl daemon-reload
    sudo systemctl enable frps
    sudo systemctl start frps
}

stop_service() {
    require_systemctl
    if systemctl is-active --quiet frps; then
        echo "正在停止 frps..."
        sudo systemctl stop frps
    else
        echo "frps 当前未运行"
    fi
}

restart_service() {
    require_systemctl
    echo "正在重启 frps..."
    sudo systemctl daemon-reload
    sudo systemctl restart frps
}

status_service() {
    require_systemctl
    sudo systemctl status frps --no-pager
}

detect_arch() {
    local arch
    arch=$(uname -m)
    if [ "$arch" = "x86_64" ]; then
        FRP_ARCH="amd64"
    elif [ "$arch" = "aarch64" ] || [ "$arch" = "arm64" ]; then
        FRP_ARCH="arm64"
    else
        echo "不支持的架构: $arch"
        exit 1
    fi
}

write_systemd_service() {
    echo "正在创建系统服务..."
    sudo tee /etc/systemd/system/frps.service > /dev/null <<EOF
[Unit]
Description=frps service
After=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/frps -c /etc/frps/frps.toml
Restart=on-failure
RestartSec=5
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF
}

deploy() {
    require_config
    load_config_values
    print_config_summary
    detect_arch

    echo "正在下载 frps ${FRP_VERSION}..."
    cd /tmp
    curl -L "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/frp_${FRP_VERSION#v}_linux_${FRP_ARCH}.tar.gz" -o frp.tar.gz
    tar xzf frp.tar.gz
    cd frp_${FRP_VERSION#v}_linux_${FRP_ARCH}

    stop_service

    echo "正在安装 frps..."
    sudo install -m 755 frps /usr/local/bin/frps.new
    sudo mv -f /usr/local/bin/frps.new /usr/local/bin/frps

    sudo mkdir -p /etc/frps

    echo "正在安装配置文件..."
    sudo install -m 600 "$CONFIG_FILE" /etc/frps/frps.toml

    write_systemd_service
    start_service

    cd /tmp
    rm -rf frp.tar.gz frp_${FRP_VERSION#v}_linux_${FRP_ARCH}

    echo ""
    echo "=========================================="
    echo "  部署完成！"
    echo "=========================================="
    echo ""
    echo "frps 已启动，端口信息:"
    echo "  - 客户端连接端口: ${FRPS_PORT:-见 /etc/frps/frps.toml}"
    echo "  - HTTP 访问端口: ${HTTP_PORT:-见 /etc/frps/frps.toml}"
    echo "  - HTTPS 访问端口: ${HTTPS_PORT:-见 /etc/frps/frps.toml}"
    echo ""
    echo "下一步："
    echo "  1. 在域名管理处添加 DNS 泛解析:"
    echo "     *.${SUB_DOMAIN_HOST:-你的子域名基域}  →  A  →  $(curl -s ifconfig.me)"
    echo ""
    echo "  2. 在 macOS 上配置 Meilink:"
    echo "     - 服务器地址: $(curl -s ifconfig.me)"
    echo "     - 端口: ${FRPS_PORT:-见 /etc/frps/frps.toml}"
    echo "     - Token: 使用 /etc/frps/frps.toml 中的 auth.token"
    echo "     - 子域名基域: ${SUB_DOMAIN_HOST:-见 /etc/frps/frps.toml}"
    echo ""
    echo "常用命令:"
    echo "  - 查看状态: ./deploy-frps.sh status"
    echo "  - 查看日志: sudo journalctl -u frps -f"
    echo "  - 重启服务: ./deploy-frps.sh restart"
    echo "  - 停止服务: ./deploy-frps.sh stop"
}

case "$COMMAND" in
    deploy)
        deploy
        ;;
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    restart)
        restart_service
        ;;
    status)
        status_service
        ;;
    help|-h|--help)
        usage
        ;;
    *)
        echo "未知命令: $COMMAND"
        echo ""
        usage
        exit 1
        ;;
esac
