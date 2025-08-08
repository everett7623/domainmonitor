#!/bin/bash

# ============================================================================
# 域名监控系统 - 一键安装脚本
# 作者: everett7623
# GitHub: https://github.com/everett7623/domainmonitor
# 描述: 自动化域名注册状态监控，支持Telegram通知
# ============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# 配置变量
INSTALL_DIR="/opt/domainmonitor"
SERVICE_NAME="domainmonitor"
GITHUB_RAW_URL="https://raw.githubusercontent.com/everett7623/domainmonitor/main"
LOG_DIR="/var/log/domainmonitor"
CONFIG_FILE="$INSTALL_DIR/config.json"

# 打印带颜色的消息
print_message() {
    echo -e "${2}${1}${NC}"
}

# 打印标题
print_header() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}           域名监控系统 - 自动安装程序 v1.0              ${CYAN}║${NC}"
    echo -e "${CYAN}║${WHITE}           GitHub: everett7623/domainmonitor             ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
}

# 打印分隔线
print_separator() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_message "❌ 此脚本需要root权限运行" "$RED"
        print_message "请使用: sudo bash $0" "$YELLOW"
        exit 1
    fi
}

# 检查系统
check_system() {
    print_message "🔍 检查系统环境..." "$BLUE"
    
    if [[ -f /etc/redhat-release ]]; then
        OS="centos"
        PKG_MANAGER="yum"
    elif cat /etc/issue | grep -q -E -i "debian|raspbian"; then
        OS="debian"
        PKG_MANAGER="apt-get"
    elif cat /etc/issue | grep -q -E -i "ubuntu"; then
        OS="ubuntu"
        PKG_MANAGER="apt-get"
    elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
        OS="centos"
        PKG_MANAGER="yum"
    elif cat /proc/version | grep -q -E -i "debian|raspbian"; then
        OS="debian"
        PKG_MANAGER="apt-get"
    elif cat /proc/version | grep -q -E -i "ubuntu"; then
        OS="ubuntu"
        PKG_MANAGER="apt-get"
    elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
        OS="centos"
        PKG_MANAGER="yum"
    else
        print_message "❌ 不支持的操作系统!" "$RED"
        exit 1
    fi
    
    print_message "✅ 检测到系统: $OS" "$GREEN"
}

# 安装依赖
install_dependencies() {
    print_message "📦 安装依赖包..." "$BLUE"
    
    # 更新包管理器
    if [[ "$PKG_MANAGER" == "apt-get" ]]; then
        apt-get update -qq
        apt-get install -y python3 python3-pip curl wget jq > /dev/null 2>&1
    elif [[ "$PKG_MANAGER" == "yum" ]]; then
        yum update -y -q
        yum install -y python3 python3-pip curl wget jq > /dev/null 2>&1
    fi
    
    # 安装Python依赖
    print_message "📚 安装Python依赖..." "$BLUE"
    pip3 install -q requests python-whois telegram-python-bot schedule colorama rich
    
    print_message "✅ 依赖安装完成" "$GREEN"
}

# 创建目录结构
create_directories() {
    print_message "📁 创建目录结构..." "$BLUE"
    
    mkdir -p $INSTALL_DIR
    mkdir -p $LOG_DIR
    mkdir -p $INSTALL_DIR/data
    
    print_message "✅ 目录创建完成" "$GREEN"
}

# 下载核心文件
download_files() {
    print_message "⬇️  下载核心文件..." "$BLUE"
    
    # 下载主程序
    wget -q -O $INSTALL_DIR/domain_monitor.py $GITHUB_RAW_URL/domain_monitor.py
    if [[ $? -ne 0 ]]; then
        print_message "❌ 下载domain_monitor.py失败" "$RED"
        exit 1
    fi
    
    # 下载管理脚本
    wget -q -O $INSTALL_DIR/domainctl.sh $GITHUB_RAW_URL/domainctl.sh
    if [[ $? -ne 0 ]]; then
        print_message "❌ 下载domainctl.sh失败" "$RED"
        exit 1
    fi
    
    chmod +x $INSTALL_DIR/domainctl.sh
    chmod +x $INSTALL_DIR/domain_monitor.py
    
    print_message "✅ 文件下载完成" "$GREEN"
}

# 配置Telegram
configure_telegram() {
    print_separator
    print_message "🤖 配置Telegram通知" "$CYAN"
    echo
    
    print_message "请提供以下信息 (如需帮助，访问 @BotFather 创建Bot):" "$YELLOW"
    echo
    
    read -p "$(echo -e ${WHITE}"请输入Telegram Bot Token: "${NC})" BOT_TOKEN
    read -p "$(echo -e ${WHITE}"请输入Telegram Chat ID: "${NC})" CHAT_ID
    
    # 创建配置文件
    cat > $CONFIG_FILE << EOF
{
    "telegram": {
        "bot_token": "$BOT_TOKEN",
        "chat_id": "$CHAT_ID",
        "enabled": true
    },
    "check_interval": 3600,
    "domains": [],
    "registrars": [
        {
            "name": "Namecheap",
            "url": "https://www.namecheap.com",
            "features": ["低价", "免费隐私保护"]
        },
        {
            "name": "Cloudflare",
            "url": "https://www.cloudflare.com/products/registrar/",
            "features": ["成本价", "免费CDN"]
        },
        {
            "name": "GoDaddy",
            "url": "https://www.godaddy.com",
            "features": ["知名度高", "24/7支持"]
        },
        {
            "name": "Google Domains",
            "url": "https://domains.google",
            "features": ["简单管理", "免费隐私保护"]
        }
    ],
    "log_level": "INFO"
}
EOF
    
    print_message "✅ Telegram配置完成" "$GREEN"
}

# 添加初始域名
add_initial_domains() {
    print_separator
    print_message "🌐 添加监控域名" "$CYAN"
    echo
    
    while true; do
        read -p "$(echo -e ${WHITE}"请输入要监控的域名 (直接回车跳过): "${NC})" DOMAIN
        
        if [[ -z "$DOMAIN" ]]; then
            break
        fi
        
        # 添加域名到配置
        python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
config['domains'].append('$DOMAIN')
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=4)
"
        print_message "✅ 已添加域名: $DOMAIN" "$GREEN"
    done
}

# 创建systemd服务
create_service() {
    print_message "⚙️  创建系统服务..." "$BLUE"
    
    cat > /etc/systemd/system/${SERVICE_NAME}.service << EOF
[Unit]
Description=Domain Monitor Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/domain_monitor.py
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/monitor.log
StandardError=append:$LOG_DIR/error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}.service
    
    print_message "✅ 系统服务创建完成" "$GREEN"
}

# 创建命令链接
create_command_link() {
    print_message "🔗 创建快捷命令..." "$BLUE"
    
    ln -sf $INSTALL_DIR/domainctl.sh /usr/local/bin/domainctl
    
    print_message "✅ 快捷命令创建完成" "$GREEN"
}

# 启动服务
start_service() {
    print_message "🚀 启动监控服务..." "$BLUE"
    
    systemctl start ${SERVICE_NAME}.service
    
    # 等待服务启动
    sleep 3
    
    if systemctl is-active --quiet ${SERVICE_NAME}.service; then
        print_message "✅ 服务启动成功" "$GREEN"
        
        # 显示最新日志
        print_message "📄 最新日志:" "$CYAN"
        tail -n 10 $LOG_DIR/monitor.log 2>/dev/null || echo "等待日志生成..."
    else
        print_message "❌ 服务启动失败，请检查日志" "$RED"
        print_message "查看日志: journalctl -u ${SERVICE_NAME} -n 50" "$YELLOW"
        print_message "或: tail -n 50 $LOG_DIR/monitor.log" "$YELLOW"
    fi
}

# 显示安装信息
show_info() {
    print_separator
    echo
    print_message "🎉 域名监控系统安装完成!" "$GREEN"
    echo
    print_message "📝 使用说明:" "$CYAN"
    echo -e "${WHITE}  • 查看状态: ${YELLOW}domainctl status${NC}"
    echo -e "${WHITE}  • 添加域名: ${YELLOW}domainctl add <domain>${NC}"
    echo -e "${WHITE}  • 删除域名: ${YELLOW}domainctl remove <domain>${NC}"
    echo -e "${WHITE}  • 列出域名: ${YELLOW}domainctl list${NC}"
    echo -e "${WHITE}  • 查看日志: ${YELLOW}domainctl logs${NC}"
    echo -e "${WHITE}  • 重启服务: ${YELLOW}domainctl restart${NC}"
    echo
    print_message "📁 安装目录: $INSTALL_DIR" "$WHITE"
    print_message "📄 配置文件: $CONFIG_FILE" "$WHITE"
    print_message "📊 日志目录: $LOG_DIR" "$WHITE"
    echo
    print_separator
    print_message "💡 提示: 使用 'domainctl help' 查看所有命令" "$YELLOW"
    print_separator
}

# 主函数
main() {
    clear
    print_header
    
    check_root
    check_system
    
    print_separator
    print_message "🚀 开始安装域名监控系统..." "$CYAN"
    print_separator
    echo
    
    install_dependencies
    create_directories
    download_files
    configure_telegram
    add_initial_domains
    create_service
    create_command_link
    start_service
    
    show_info
}

# 错误处理
trap 'print_message "❌ 安装过程中出现错误" "$RED"; exit 1' ERR

# 运行主函数
main
