#!/bin/bash
# ====================================
# Domain Monitor 安装脚本
# 作者: everett7623
# 描述: 自动安装和配置域名监控系统
# ====================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# 配置变量
INSTALL_DIR="/opt/domainmonitor"
SERVICE_NAME="domainmonitor"
GITHUB_USER="everett7623"
GITHUB_REPO="domainmonitor"
GITHUB_RAW="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"

# 打印横幅
print_banner() {
    echo -e "${PURPLE}"
    echo "╔══════════════════════════════════════════╗"
    echo "║        Domain Monitor 安装程序           ║"
    echo "║         域名状态监控系统 v1.0            ║"
    echo "║      Author: everett7623                 ║"
    echo "╚══════════════════════════════════════════╝"
    echo -e "${NC}"
}

# 打印信息函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# 检查系统要求
check_requirements() {
    print_info "检查系统要求..."
    
    # 检查是否为 root 用户
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要 root 权限运行"
        echo -e "${YELLOW}请使用: sudo bash $0${NC}"
        exit 1
    fi
    
    # 检查 Python
    if ! command -v python3 &> /dev/null; then
        print_error "未找到 Python3"
        print_info "正在安装 Python3..."
        apt-get update && apt-get install -y python3 python3-pip || yum install -y python3 python3-pip
    else
        print_success "Python3 已安装"
    fi
    
    # 检查 pip
    if ! command -v pip3 &> /dev/null; then
        print_error "未找到 pip3"
        print_info "正在安装 pip3..."
        apt-get install -y python3-pip || yum install -y python3-pip
    else
        print_success "pip3 已安装"
    fi
    
    # 检查 systemd
    if ! command -v systemctl &> /dev/null; then
        print_error "系统不支持 systemd"
        exit 1
    else
        print_success "systemd 已就绪"
    fi
}

# 安装 Python 依赖
install_dependencies() {
    print_info "安装 Python 依赖包..."
    
    # 创建临时 requirements.txt
    cat > /tmp/requirements.txt << EOF
python-whois==0.9.3
python-telegram-bot==20.7
schedule==1.2.0
dnspython==2.4.2
requests==2.31.0
EOF
    
    pip3 install -r /tmp/requirements.txt
    rm -f /tmp/requirements.txt
    
    print_success "依赖包安装完成"
}

# 创建安装目录
create_directories() {
    print_info "创建安装目录..."
    
    mkdir -p ${INSTALL_DIR}/{logs,data}
    chmod 755 ${INSTALL_DIR}
    
    print_success "目录创建完成"
}

# 下载程序文件
download_files() {
    print_info "下载程序文件..."
    
    # 下载主程序
    print_info "下载 domain_monitor.py..."
    curl -sSL "${GITHUB_RAW}/domain_monitor.py" -o "${INSTALL_DIR}/domain_monitor.py"
    chmod +x "${INSTALL_DIR}/domain_monitor.py"
    
    # 下载管理脚本
    print_info "下载 domainctl.sh..."
    curl -sSL "${GITHUB_RAW}/domainctl.sh" -o "/usr/local/bin/domainctl"
    chmod +x "/usr/local/bin/domainctl"
    
    print_success "文件下载完成"
}

# 配置 Telegram
configure_telegram() {
    print_info "配置 Telegram 通知..."
    echo
    echo -e "${CYAN}请准备以下信息：${NC}"
    echo -e "${WHITE}1. Telegram Bot Token (从 @BotFather 获取)${NC}"
    echo -e "${WHITE}2. Telegram Chat ID (您的用户ID或群组ID)${NC}"
    echo
    
    read -p "请输入 Telegram Bot Token: " bot_token
    read -p "请输入 Telegram Chat ID: " chat_id
    
    # 创建配置文件
    cat > "${INSTALL_DIR}/config.json" << EOF
{
    "telegram": {
        "bot_token": "${bot_token}",
        "chat_id": "${chat_id}"
    },
    "check_interval": 3600,
    "domains": []
}
EOF
    
    chmod 600 "${INSTALL_DIR}/config.json"
    print_success "Telegram 配置完成"
}

# 创建 systemd 服务
create_service() {
    print_info "创建系统服务..."
    
    cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=Domain Monitor Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${INSTALL_DIR}
ExecStart=/usr/bin/python3 ${INSTALL_DIR}/domain_monitor.py
Restart=always
RestartSec=10
StandardOutput=append:${INSTALL_DIR}/logs/monitor.log
StandardError=append:${INSTALL_DIR}/logs/error.log

[Install]
WantedBy=multi-user.target
EOF
    
    systemctl daemon-reload
    systemctl enable ${SERVICE_NAME}
    
    print_success "系统服务创建完成"
}

# 初始化域名列表
init_domains() {
    print_info "初始化域名列表..."
    echo
    echo -e "${CYAN}是否现在添加要监控的域名？${NC}"
    read -p "输入 y 添加域名，输入 n 稍后添加 [y/n]: " add_now
    
    if [[ "$add_now" == "y" || "$add_now" == "Y" ]]; then
        echo -e "${WHITE}请输入要监控的域名（每行一个，输入空行结束）：${NC}"
        
        domains=()
        while true; do
            read -p "> " domain
            if [[ -z "$domain" ]]; then
                break
            fi
            domains+=("$domain")
        done
        
        if [[ ${#domains[@]} -gt 0 ]]; then
            for domain in "${domains[@]}"; do
                /usr/local/bin/domainctl add "$domain"
            done
            print_success "已添加 ${#domains[@]} 个域名"
        fi
    fi
}

# 显示安装信息
show_installation_info() {
    echo
    echo -e "${GREEN}╔══════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║        安装成功！                        ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════╝${NC}"
    echo
    echo -e "${CYAN}安装信息：${NC}"
    echo -e "${WHITE}• 安装目录: ${INSTALL_DIR}${NC}"
    echo -e "${WHITE}• 配置文件: ${INSTALL_DIR}/config.json${NC}"
    echo -e "${WHITE}• 日志目录: ${INSTALL_DIR}/logs${NC}"
    echo -e "${WHITE}• 管理命令: domainctl${NC}"
    echo
    echo -e "${CYAN}常用命令：${NC}"
    echo -e "${WHITE}• 查看状态: domainctl status${NC}"
    echo -e "${WHITE}• 添加域名: domainctl add example.com${NC}"
    echo -e "${WHITE}• 删除域名: domainctl remove example.com${NC}"
    echo -e "${WHITE}• 域名列表: domainctl list${NC}"
    echo -e "${WHITE}• 查看日志: domainctl logs${NC}"
    echo -e "${WHITE}• 启动服务: domainctl start${NC}"
    echo -e "${WHITE}• 停止服务: domainctl stop${NC}"
    echo
    echo -e "${YELLOW}提示：${NC}"
    echo -e "${WHITE}• 使用 'domainctl help' 查看所有可用命令${NC}"
    echo -e "${WHITE}• 配置文件中可以修改检查间隔时间${NC}"
    echo -e "${WHITE}• 日志文件会自动轮转，无需手动清理${NC}"
    echo
}

# 主安装流程
main() {
    clear
    print_banner
    
    print_info "开始安装 Domain Monitor..."
    echo
    
    # 执行安装步骤
    check_requirements
    install_dependencies
    create_directories
    download_files
    configure_telegram
    create_service
    init_domains
    
    # 启动服务
    print_info "启动服务..."
    systemctl start ${SERVICE_NAME}
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        print_success "服务启动成功"
    else
        print_error "服务启动失败，请检查日志"
        echo -e "${YELLOW}查看日志: journalctl -u ${SERVICE_NAME} -f${NC}"
    fi
    
    # 显示安装信息
    show_installation_info
}

# 错误处理
trap 'print_error "安装过程中发生错误"; exit 1' ERR

# 运行主函数
main
