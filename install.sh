#!/bin/bash
#
# Domain Monitor 一键安装脚本
# GitHub: https://github.com/everett7623/domainmonitor
# 
# 使用方法:
# bash <(curl -sSL https://raw.githubusercontent.com/everett7623/domainmonitor/main/install.sh)
#
# 功能说明:
# - 自动检测并安装依赖
# - 下载并配置域名监控程序
# - 设置系统定时任务
# - 提供友好的交互界面
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 配置变量
INSTALL_DIR="$HOME/.domainmonitor"
CONFIG_FILE="$INSTALL_DIR/config.json"
LOG_DIR="$INSTALL_DIR/logs"
GITHUB_RAW_URL="https://raw.githubusercontent.com/everett7623/domainmonitor/main"
PYTHON_MIN_VERSION="3.7"

# 打印带颜色的消息
print_msg() {
    local color=$1
    local msg=$2
    echo -e "${color}${msg}${NC}"
}

# 打印标题
print_title() {
    echo
    print_msg "$PURPLE" "=========================================="
    print_msg "$CYAN" "       Domain Monitor 安装向导"
    print_msg "$PURPLE" "=========================================="
    echo
}

# 打印错误并退出
error_exit() {
    print_msg "$RED" "❌ 错误: $1"
    exit 1
}

# 检查命令是否存在
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# 比较版本号
version_ge() {
    [ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# 检查 Python 版本
check_python() {
    print_msg "$BLUE" "🔍 检查 Python 环境..."
    
    if command_exists python3; then
        PYTHON_CMD="python3"
    elif command_exists python; then
        PYTHON_CMD="python"
    else
        error_exit "未找到 Python，请先安装 Python 3.7 或更高版本"
    fi
    
    # 获取 Python 版本
    PYTHON_VERSION=$($PYTHON_CMD -c 'import sys; print(".".join(map(str, sys.version_info[:2])))')
    
    if ! version_ge "$PYTHON_VERSION" "$PYTHON_MIN_VERSION"; then
        error_exit "Python 版本过低，需要 $PYTHON_MIN_VERSION 或更高版本，当前版本: $PYTHON_VERSION"
    fi
    
    print_msg "$GREEN" "✅ Python $PYTHON_VERSION 符合要求"
}

# 检查并安装 pip
check_pip() {
    print_msg "$BLUE" "🔍 检查 pip..."
    
    if ! $PYTHON_CMD -m pip --version >/dev/null 2>&1; then
        print_msg "$YELLOW" "⚠️  未找到 pip，正在安装..."
        curl -sS https://bootstrap.pypa.io/get-pip.py | $PYTHON_CMD || error_exit "pip 安装失败"
    fi
    
    print_msg "$GREEN" "✅ pip 已就绪"
}

# 创建目录结构
create_directories() {
    print_msg "$BLUE" "📁 创建目录结构..."
    
    mkdir -p "$INSTALL_DIR"
    mkdir -p "$LOG_DIR"
    mkdir -p "$INSTALL_DIR/bin"
    
    print_msg "$GREEN" "✅ 目录创建成功"
}

# 安装 Python 依赖
install_dependencies() {
    print_msg "$BLUE" "📦 安装依赖包..."
    
    # 创建 requirements.txt
    cat > "$INSTALL_DIR/requirements.txt" << EOF
requests>=2.28.0
python-whois>=0.8.0
schedule>=1.2.0
python-telegram-bot>=20.0
colorama>=0.4.6
tabulate>=0.9.0
EOF
    
    # 安装依赖
    $PYTHON_CMD -m pip install -r "$INSTALL_DIR/requirements.txt" --user || error_exit "依赖安装失败"
    
    print_msg "$GREEN" "✅ 依赖安装成功"
}

# 下载主程序
download_main_program() {
    print_msg "$BLUE" "📥 下载主程序..."
    
    # 下载 domainmonitor.py
    curl -sS -o "$INSTALL_DIR/domainmonitor.py" "$GITHUB_RAW_URL/domainmonitor.py" || error_exit "主程序下载失败"
    
    # 设置执行权限
    chmod +x "$INSTALL_DIR/domainmonitor.py"
    
    print_msg "$GREEN" "✅ 主程序下载成功"
}

# 创建管理脚本
create_management_script() {
    print_msg "$BLUE" "🔧 创建管理脚本..."
    
    cat > "$INSTALL_DIR/bin/domainmonitor" << EOF
#!/bin/bash
cd "$INSTALL_DIR"
$PYTHON_CMD domainmonitor.py "\$@"
EOF
    
    chmod +x "$INSTALL_DIR/bin/domainmonitor"
    
    # 创建软链接
    if [ -d "$HOME/.local/bin" ]; then
        ln -sf "$INSTALL_DIR/bin/domainmonitor" "$HOME/.local/bin/domainmonitor"
    elif [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
        ln -sf "$INSTALL_DIR/bin/domainmonitor" "/usr/local/bin/domainmonitor"
    fi
    
    print_msg "$GREEN" "✅ 管理脚本创建成功"
}

# 配置初始设置
configure_initial_settings() {
    print_msg "$CYAN" "\n📝 初始配置"
    print_msg "$YELLOW" "请按照提示完成初始配置："
    echo
    
    # 域名列表
    domains=()
    while true; do
        read -p "$(echo -e ${CYAN}"请输入要监控的域名 (直接回车完成输入): "${NC})" domain
        if [ -z "$domain" ]; then
            if [ ${#domains[@]} -eq 0 ]; then
                print_msg "$RED" "⚠️  至少需要添加一个域名"
                continue
            else
                break
            fi
        fi
        domains+=("$domain")
        print_msg "$GREEN" "✅ 已添加: $domain"
    done
    
    # Telegram 配置
    echo
    print_msg "$CYAN" "📱 Telegram Bot 配置 (可选，直接回车跳过)"
    read -p "$(echo -e ${CYAN}"Bot Token: "${NC})" bot_token
    
    chat_id=""
    if [ -n "$bot_token" ]; then
        read -p "$(echo -e ${CYAN}"Chat ID: "${NC})" chat_id
    fi
    
    # 创建配置文件
    cat > "$CONFIG_FILE" << EOF
{
    "domains": $(printf '%s\n' "${domains[@]}" | jq -R . | jq -s .),
    "telegram": {
        "bot_token": "$bot_token",
        "chat_id": "$chat_id"
    },
    "check_interval": 3600,
    "log_level": "INFO",
    "registrars": [
        {
            "name": "Namecheap",
            "url": "https://www.namecheap.com",
            "features": ["价格优惠", "免费隐私保护", "支持支付宝"]
        },
        {
            "name": "Cloudflare",
            "url": "https://www.cloudflare.com/products/registrar/",
            "features": ["成本价注册", "免费 CDN", "无隐藏费用"]
        },
        {
            "name": "阿里云",
            "url": "https://wanwang.aliyun.com",
            "features": ["国内访问快", "中文支持", "企业服务"]
        }
    ]
}
EOF
    
    print_msg "$GREEN" "✅ 配置文件创建成功"
}

# 设置定时任务
setup_cron() {
    print_msg "$BLUE" "⏰ 设置定时任务..."
    
    # 创建 systemd service (如果支持)
    if command_exists systemctl && [ -d "$HOME/.config/systemd/user" ]; then
        cat > "$HOME/.config/systemd/user/domainmonitor.service" << EOF
[Unit]
Description=Domain Monitor Service
After=network.target

[Service]
Type=simple
ExecStart=$PYTHON_CMD $INSTALL_DIR/domainmonitor.py --daemon
Restart=always
RestartSec=300

[Install]
WantedBy=default.target
EOF
        
        systemctl --user daemon-reload
        systemctl --user enable domainmonitor.service
        systemctl --user start domainmonitor.service
        
        print_msg "$GREEN" "✅ Systemd 服务已创建并启动"
    else
        # 使用 crontab
        CRON_CMD="*/30 * * * * $PYTHON_CMD $INSTALL_DIR/domainmonitor.py --check >/dev/null 2>&1"
        (crontab -l 2>/dev/null | grep -v "domainmonitor.py"; echo "$CRON_CMD") | crontab -
        
        print_msg "$GREEN" "✅ Crontab 定时任务已设置 (每30分钟检查一次)"
    fi
}

# 显示安装摘要
show_summary() {
    echo
    print_msg "$PURPLE" "=========================================="
    print_msg "$GREEN" "🎉 Domain Monitor 安装成功！"
    print_msg "$PURPLE" "=========================================="
    echo
    print_msg "$CYAN" "📋 安装摘要："
    print_msg "$YELLOW" "  • 安装目录: $INSTALL_DIR"
    print_msg "$YELLOW" "  • 配置文件: $CONFIG_FILE"
    print_msg "$YELLOW" "  • 日志目录: $LOG_DIR"
    print_msg "$YELLOW" "  • 监控域名: ${#domains[@]} 个"
    
    if [ -n "$bot_token" ]; then
        print_msg "$YELLOW" "  • Telegram: 已配置"
    else
        print_msg "$YELLOW" "  • Telegram: 未配置"
    fi
    
    echo
    print_msg "$CYAN" "🚀 使用方法："
    print_msg "$GREEN" "  运行 domainmonitor 进入管理菜单"
    echo
    print_msg "$BLUE" "💡 提示："
    print_msg "$YELLOW" "  • 首次运行可能需要重新加载终端或运行: source ~/.bashrc"
    print_msg "$YELLOW" "  • 查看日志: tail -f $LOG_DIR/domainmonitor.log"
    print_msg "$YELLOW" "  • 获取帮助: domainmonitor --help"
    echo
}

# 主安装流程
main() {
    clear
    print_title
    
    # 检查系统要求
    check_python
    check_pip
    
    # 检查是否已安装
    if [ -d "$INSTALL_DIR" ]; then
        print_msg "$YELLOW" "⚠️  检测到已有安装"
        read -p "$(echo -e ${CYAN}"是否覆盖安装？(y/N): "${NC})" -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_msg "$YELLOW" "安装已取消"
            exit 0
        fi
        rm -rf "$INSTALL_DIR"
    fi
    
    # 执行安装步骤
    create_directories
    install_dependencies
    download_main_program
    create_management_script
    configure_initial_settings
    setup_cron
    
    # 显示安装摘要
    show_summary
}

# 运行主函数
main
