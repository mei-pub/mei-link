#!/bin/bash
set -e

# ============================================
# Meilink frps 服务端一键部署脚本
# 在 VPS 上运行此脚本即可完成部署
# ============================================

# 配置区域 - 修改以下参数
FRP_VERSION="v0.70.0"
FRPS_PORT=7000          # 客户端连接端口
HTTP_PORT=8080          # HTTP 子域名访问端口
HTTPS_PORT=8443         # HTTPS 子域名访问端口
AUTH_TOKEN="your-secret-token-here"  # 认证密钥，改成你自己的！
SUB_DOMAIN_HOST="tunnel.yourdomain.com"  # 子域名基域，改成你的域名

echo "=========================================="
echo "  Meilink frps 服务端部署"
echo "=========================================="
echo ""
echo "配置信息:"
echo "  - 客户端端口: $FRPS_PORT"
echo "  - HTTP 端口: $HTTP_PORT"
echo "  - HTTPS 端口: $HTTPS_PORT"
echo "  - 子域名基域: $SUB_DOMAIN_HOST"
echo ""

# 检测系统架构
ARCH=$(uname -m)
if [ "$ARCH" = "x86_64" ]; then
    FRP_ARCH="amd64"
elif [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    FRP_ARCH="arm64"
else
    echo "不支持的架构: $ARCH"
    exit 1
fi

# 下载 frps
echo "正在下载 frps ${FRP_VERSION}..."
cd /tmp
curl -L "https://github.com/fatedier/frp/releases/download/${FRP_VERSION}/frp_${FRP_VERSION#v}_linux_${FRP_ARCH}.tar.gz" -o frp.tar.gz
tar xzf frp.tar.gz
cd frp_${FRP_VERSION#v}_linux_${FRP_ARCH}

# 安装 frps
echo "正在安装 frps..."
sudo cp frps /usr/local/bin/
sudo chmod +x /usr/local/bin/frps

# 创建配置目录
sudo mkdir -p /etc/frps

# 生成配置文件
echo "正在生成配置文件..."
sudo tee /etc/frps/frps.toml > /dev/null <<EOF
# frps 配置文件 - 由 Meilink 部署脚本生成

# 监听端口（客户端连接端口）
bindPort = $FRPS_PORT

# HTTP vhost 端口（子域名访问）
vhostHTTPPort = $HTTP_PORT

# HTTPS vhost 端口
vhostHTTPSPort = $HTTPS_PORT

# 子域名基域（需要在 DNS 配置泛解析）
subDomainHost = "$SUB_DOMAIN_HOST"

# 认证配置
auth.method = "token"
auth.token = "$AUTH_TOKEN"
EOF

# 创建 systemd 服务
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

# 启动服务
echo "正在启动 frps..."
sudo systemctl daemon-reload
sudo systemctl enable frps
sudo systemctl start frps

# 清理
cd /tmp
rm -rf frp.tar.gz frp_${FRP_VERSION#v}_linux_${FRP_ARCH}

echo ""
echo "=========================================="
echo "  部署完成！"
echo "=========================================="
echo ""
echo "frps 已启动，端口信息:"
echo "  - 客户端连接端口: $FRPS_PORT"
echo "  - HTTP 访问端口: $HTTP_PORT"
echo "  - HTTPS 访问端口: $HTTPS_PORT"
echo ""
echo "下一步："
echo "  1. 在域名管理处添加 DNS 泛解析:"
echo "     *.$SUB_DOMAIN_HOST  →  A  →  $(curl -s ifconfig.me)"
echo ""
echo "  2. 在 macOS 上配置 Meilink:"
echo "     - 服务器地址: $(curl -s ifconfig.me)"
echo "     - 端口: $FRPS_PORT"
echo "     - Token: $AUTH_TOKEN"
echo "     - 子域名基域: $SUB_DOMAIN_HOST"
echo ""
echo "常用命令:"
echo "  - 查看状态: sudo systemctl status frps"
echo "  - 查看日志: sudo journalctl -u frps -f"
echo "  - 重启服务: sudo systemctl restart frps"
echo "  - 停止服务: sudo systemctl stop frps"
