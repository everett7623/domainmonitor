#!/bin/bash
# ================================================================================
# DomainMonitor - 域名状态监控系统安装脚本
# 
# 作者: everett7623
# GitHub: https://github.com/everett7623/domainmonitor
# 版本: v1.0.0
# 
# 描述: 自动监控域名注册状态，支持 Telegram 通知
# 使用: bash <(curl -sSL https://raw.githubusercontent.com/everett7623/domainmonitor/main/install.sh)
# ================================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
INSTALL_DIR="/opt/domainmonitor"
SERVICE_NAME="domainmonitor"
GITHUB_USER="everett7623"
GITHUB_REPO="domainmonitor"
GITHUB_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}"
RAW_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"

# 打印带颜色的消息
print_msg() {
    echo -e "${2}${1}${NC}"
}

# 打印标题
print_header() {
    echo
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║              DomainMonitor 域名监控系统 v1.0.0            ║${NC}"
    echo -e "${CYAN}║                  Author: everett7623                      ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo
}

# 检查系统要求
check_requirements() {
    print_msg "▶ 检查系统要求..." "$BLUE"
    
    # 检查是否为 root 用户
    if [[ $EUID -ne 0 ]]; then
        print_msg "✗ 错误: 此脚本需要 root 权限运行" "$RED"
        print_msg "  请使用: sudo bash $0" "$YELLOW"
        exit 1
    fi
    
    # 检查操作系统
    if [[ ! -f /etc/os-release ]]; then
        print_msg "✗ 错误: 无法检测操作系统类型" "$RED"
        exit 1
    fi
    
    . /etc/os-release
    OS=$ID
    OS_VERSION=$VERSION_ID
    
    print_msg "✓ 检测到系统: $PRETTY_NAME" "$GREEN"
    
    # 检查 Python
    if ! command -v python3 &> /dev/null; then
        print_msg "✗ Python3 未安装，正在安装..." "$YELLOW"
        case $OS in
            ubuntu|debian)
                apt-get update && apt-get install -y python3 python3-pip python3-venv
                ;;
            centos|rhel|fedora)
                yum install -y python3 python3-pip
                ;;
            *)
                print_msg "✗ 不支持的操作系统: $OS" "$RED"
                exit 1
                ;;
        esac
    else
        PYTHON_VERSION=$(python3 --version | cut -d' ' -f2)
        print_msg "✓ Python 版本: $PYTHON_VERSION" "$GREEN"
    fi
    
    # 检查 Git
    if ! command -v git &> /dev/null; then
        print_msg "✗ Git 未安装，正在安装..." "$YELLOW"
        case $OS in
            ubuntu|debian)
                apt-get install -y git
                ;;
            centos|rhel|fedora)
                yum install -y git
                ;;
        esac
    fi
    
    # 检查 whois
    if ! command -v whois &> /dev/null; then
        print_msg "✗ whois 未安装，正在安装..." "$YELLOW"
        case $OS in
            ubuntu|debian)
                apt-get install -y whois
                ;;
            centos|rhel|fedora)
                yum install -y whois
                ;;
        esac
    fi
    
    print_msg "✓ 系统要求检查完成" "$GREEN"
}

# 创建安装目录
create_directories() {
    print_msg "\n▶ 创建安装目录..." "$BLUE"
    
    # 创建主目录
    mkdir -p $INSTALL_DIR/{logs,data,config}
    
    # 设置权限
    chmod 755 $INSTALL_DIR
    chmod 755 $INSTALL_DIR/{logs,data,config}
    
    print_msg "✓ 目录创建完成" "$GREEN"
}

# 下载主程序
download_program() {
    print_msg "\n▶ 下载程序文件..." "$BLUE"
    
    cd $INSTALL_DIR
    
    # 下载主程序
    print_msg "  下载 domainmonitor.py..." "$CYAN"
    curl -sSL "${RAW_URL}/domainmonitor.py" -o domainmonitor.py
    chmod +x domainmonitor.py
    
    # 下载管理脚本
    print_msg "  下载 domainctl.sh..." "$CYAN"
    curl -sSL "${RAW_URL}/domainctl.sh" -o domainctl.sh
    chmod +x domainctl.sh
    
    # 创建软链接
    ln -sf $INSTALL_DIR/domainctl.sh /usr/local/bin/domainctl
    
    print_msg "✓ 程序下载完成" "$GREEN"
}

# 创建 Python 虚拟环境
setup_python_env() {
    print_msg "\n▶ 设置 Python 环境..." "$BLUE"
    
    cd $INSTALL_DIR
    
    # 创建虚拟环境
    python3 -m venv venv
    
    # 激活虚拟环境并安装依赖
    source venv/bin/activate
    pip install --upgrade pip
    
    # 下载并安装依赖
    print_msg "  安装 Python 依赖包..." "$CYAN"
    curl -sSL "${RAW_URL}/requirements.txt" -o requirements.txt
    pip install -r requirements.txt
    
    deactivate
    
    print_msg "✓ Python 环境设置完成" "$GREEN"
}

# 配置 Telegram Bot
configure_telegram() {
    print_msg "\n▶ 配置 Telegram Bot..." "$BLUE"
    
    echo -e "${YELLOW}请准备您的 Telegram Bot 信息：${NC}"
    echo -e "${CYAN}1. 在 Telegram 中找到 @BotFather${NC}"
    echo -e "${CYAN}2. 发送 /newbot 创建新机器人${NC}"
    echo -e "${CYAN}3. 获取 Bot Token${NC}"
    echo -e "${CYAN}4. 获取您的 Chat ID (可以通过 @userinfobot 获取)${NC}"
    echo
    
    read -p "请输入 Telegram Bot Token: " BOT_TOKEN
    read -p "请输入 Telegram Chat ID: " CHAT_ID
    
    # 创建配置文件
    cat > $INSTALL_DIR/config/config.json << EOF
{
    "telegram": {
        "bot_token": "$BOT_TOKEN",
        "chat_id": "$CHAT_ID"
    },
    "check_interval": 300,
    "domains": [],
    "registrars": [
        {
            "name": "Namecheap",
            "url": "https://www.namecheap.com",
            "features": ["价格实惠", "免费隐私保护", "支持支付宝"]
        },
        {
            "name": "GoDaddy",
            "url": "https://www.godaddy.com",
            "features": ["全球最大注册商", "24/7客服", "域名管理方便"]
        },
        {
            "name": "Cloudflare",
            "url": "https://www.cloudflare.com/products/registrar/",
            "features": ["成本价注册", "免费CDN", "安全性高"]
        },
        {
            "name": "阿里云",
            "url": "https://wanwang.aliyun.com",
            "features": ["国内领先", "备案方便", "企业服务完善"]
        }
    ]
}
EOF
    
    print_msg "✓ Telegram 配置完成" "$GREEN"
}

# 添加域名
add_initial_domains() {
    print_msg "\n▶ 添加监控域名..." "$BLUE"
    
    echo -e "${YELLOW}请输入要监控的域名（每行一个，输入空行结束）：${NC}"
    
    DOMAINS=()
    while true; do
        read -p "> " domain
        if [[ -z "$domain" ]]; then
            break
        fi
        DOMAINS+=("$domain")
    done
    
    if [[ ${#DOMAINS[@]} -gt 0 ]]; then
        # 使用 Python 脚本添加域名
        cd $INSTALL_DIR
        source venv/bin/activate
        
        for domain in "${DOMAINS[@]}"; do
            python3 -c "
import json
with open('config/config.json', 'r') as f:
    config = json.load(f)
config['domains'].append('$domain')
with open('config/config.json', 'w') as f:
    json.dump(config, f, indent=4)
"
            print_msg "  ✓ 已添加: $domain" "$GREEN"
        done
        
        deactivate
    fi
}

# 创建 systemd 服务
create_service() {
    print_msg "\n▶ 创建系统服务..." "$BLUE"
    
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=DomainMonitor - 域名状态监控服务
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
Environment="PATH=$INSTALL_DIR/venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
ExecStart=$INSTALL_DIR/venv/bin/python $INSTALL_DIR/domainmonitor.py
Restart=always
RestartSec=30
StandardOutput=append:$INSTALL_DIR/logs/domainmonitor.log
StandardError=append:$INSTALL_DIR/logs/domainmonitor.error.log

[Install]
WantedBy=multi-user.target
EOF
    
    # 重载 systemd
    systemctl daemon-reload
    
    # 启用服务
    systemctl enable ${SERVICE_NAME}.service
    
    print_msg "✓ 系统服务创建完成" "$GREEN"
}

# 显示安装摘要
show_summary() {
    echo
    echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                    安装完成！                             ║${NC}"
    echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
    echo
    echo -e "${GREEN}安装路径:${NC} $INSTALL_DIR"
    echo -e "${GREEN}配置文件:${NC} $INSTALL_DIR/config/config.json"
    echo -e "${GREEN}日志文件:${NC} $INSTALL_DIR/logs/"
    echo
    echo -e "${YELLOW}常用命令：${NC}"
    echo -e "  ${CYAN}domainctl start${NC}    - 启动服务"
    echo -e "  ${CYAN}domainctl stop${NC}     - 停止服务"
    echo -e "  ${CYAN}domainctl status${NC}   - 查看状态"
    echo -e "  ${CYAN}domainctl add${NC}      - 添加域名"
    echo -e "  ${CYAN}domainctl remove${NC}   - 删除域名"
    echo -e "  ${CYAN}domainctl list${NC}     - 列出域名"
    echo -e "  ${CYAN}domainctl check${NC}    - 立即检查"
    echo -e "  ${CYAN}domainctl logs${NC}     - 查看日志"
    echo
    echo -e "${PURPLE}GitHub: ${GITHUB_URL}${NC}"
    echo
}

# 询问是否启动服务
ask_start_service() {
    echo
    read -p "是否立即启动监控服务？[Y/n] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
        systemctl start ${SERVICE_NAME}
        print_msg "✓ 服务已启动" "$GREEN"
        systemctl status ${SERVICE_NAME} --no-pager
    fi
}

# 主函数
main() {
    clear
    print_header
    
    # 执行安装步骤
    check_requirements
    create_directories
    download_program
    setup_python_env
    configure_telegram
    add_initial_domains
    create_service
    
    # 显示摘要
    show_summary
    
    # 询问是否启动
    ask_start_service
    
    print_msg "\n🎉 DomainMonitor 安装成功！" "$GREEN"
}

# 运行主函数
main
