#!/bin/bash

# 域名监控服务 VPS 部署脚本
# 支持 Ubuntu/Debian 系统

set -e

echo "====================================="
echo "域名监控服务部署脚本"
echo "====================================="

# 检查是否为 root 用户
if [ "$EUID" -eq 0 ]; then
    echo "警告: 不建议以 root 用户运行此脚本"
    read -p "是否继续？(y/N): " continue_as_root
    if [[ ! $continue_as_root =~ ^[Yy]$ ]]; then
        echo "脚本已取消"
        exit 1
    fi
fi

# 检测系统类型
if [ -f /etc/debian_version ]; then
    echo "检测到 Debian/Ubuntu 系统"
    PKG_MANAGER="apt-get"
elif [ -f /etc/redhat-release ]; then
    echo "检测到 RedHat/CentOS 系统"
    PKG_MANAGER="yum"
    echo "警告: 此脚本主要为 Ubuntu/Debian 设计，CentOS 支持可能不完整"
else
    echo "不支持的系统类型"
    exit 1
fi

# 更新系统
echo "1. 更新系统包..."
if [ "$PKG_MANAGER" = "apt-get" ]; then
    sudo apt-get update
    sudo apt-get upgrade -y
else
    sudo yum update -y
fi

# 安装必要的软件
echo "2. 安装 Python 3 和依赖..."
if [ "$PKG_MANAGER" = "apt-get" ]; then
    sudo apt-get install -y python3 python3-pip python3-venv git supervisor curl wget
else
    sudo yum install -y python3 python3-pip git supervisor curl wget
fi

# 创建项目目录
PROJECT_DIR="/opt/domain-monitor"
echo "3. 创建项目目录: $PROJECT_DIR"
sudo mkdir -p $PROJECT_DIR
sudo chown $USER:$USER $PROJECT_DIR
cd $PROJECT_DIR

# 备份现有配置（如果存在）
if [ -f "config.env" ]; then
    echo "发现现有配置文件，创建备份..."
    cp config.env config.env.backup.$(date +%Y%m%d_%H%M%S)
fi

# 创建虚拟环境
echo "4. 创建 Python 虚拟环境..."
python3 -m venv venv
source venv/bin/activate

# 安装 Python 依赖
echo "5. 安装 Python 依赖包..."
pip install --upgrade pip
pip install python-whois requests schedule

# 复制项目文件
echo "6. 复制项目文件..."
# 检查是否有源文件需要复制
SOURCE_DIR=""
if [ -d "/tmp/domain-monitor" ]; then
    SOURCE_DIR="/tmp/domain-monitor"
elif [ -d "$HOME/domain-monitor" ]; then
    SOURCE_DIR="$HOME/domain-monitor"
fi

if [ -n "$SOURCE_DIR" ]; then
    echo "从 $SOURCE_DIR 复制文件..."
    cp -r $SOURCE_DIR/* .
else
    echo "未找到源文件目录，请确保项目文件已上传到服务器"
    echo "或者使用 git clone 命令下载项目文件"
    read -p "是否从 GitHub 克隆项目？(y/N): " clone_from_git
    if [[ $clone_from_git =~ ^[Yy]$ ]]; then
        read -p "请输入 GitHub 仓库地址: " repo_url
        if [ -n "$repo_url" ]; then
            git clone $repo_url .
        fi
    fi
fi

# 创建配置文件
if [ ! -f "config.env" ]; then
    echo "7. 配置 Telegram Bot..."
    
    # 交互式输入敏感信息
    read -p "请输入 Telegram Bot Token: " bot_token
    while [ -z "$bot_token" ]; do
        echo "Bot Token 不能为空！"
        read -p "请输入 Telegram Bot Token: " bot_token
    done
    
    read -p "请输入 Telegram Chat ID: " chat_id
    while [ -z "$chat_id" ]; do
        echo "Chat ID 不能为空！"
        read -p "请输入 Telegram Chat ID: " chat_id
    done
    
    read -p "请输入检查间隔（分钟，默认60）: " check_interval
    if [ -z "$check_interval" ]; then
        check_interval=60
    fi
    
    # 询问是否启用邮件通知
    read -p "是否启用邮件通知？(y/N): " enable_email
    if [[ $enable_email =~ ^[Yy]$ ]]; then
        read -p "请输入 SMTP 服务器: " smtp_server
        read -p "请输入 SMTP 端口（默认587）: " smtp_port
        if [ -z "$smtp_port" ]; then
            smtp_port=587
        fi
        read -p "请输入发件人邮箱: " sender_email
        read -s -p "请输入邮箱密码: " email_password
        echo
        read -p "请输入收件人邮箱: " receiver_email
    fi
    
    # 创建配置文件
    cat > config.env << EOF
# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=$bot_token
TELEGRAM_CHAT_ID=$chat_id

# 检查间隔（分钟）
CHECK_INTERVAL_MINUTES=$check_interval

# 日志级别 (DEBUG, INFO, WARNING, ERROR)
LOG_LEVEL=INFO

# 最大重试次数
MAX_RETRIES=3

# 超时设置（秒）
REQUEST_TIMEOUT=30
EOF

    # 如果启用了邮件通知，添加邮件配置
    if [[ $enable_email =~ ^[Yy]$ ]]; then
        cat >> config.env << EOF

# 邮件通知配置
ENABLE_EMAIL=true
SMTP_SERVER=$smtp_server
SMTP_PORT=$smtp_port
SENDER_EMAIL=$sender_email
EMAIL_PASSWORD=$email_password
RECEIVER_EMAIL=$receiver_email
EOF
    else
        echo "ENABLE_EMAIL=false" >> config.env
    fi
    
    # 设置配置文件权限
    chmod 600 config.env
    echo "配置文件已创建并设置权限为 600（仅所有者可读写）"
else
    echo "7. 配置文件已存在，跳过配置步骤"
fi

# 创建域名列表文件
if [ ! -f "domains.json" ]; then
    echo "8. 创建域名列表文件..."
    cat > domains.json << 'EOF'
{}
EOF
fi

# 创建日志目录
echo "9. 创建日志目录..."
sudo mkdir -p /var/log/domain-monitor
sudo chown $USER:$USER /var/log/domain-monitor

# 创建管理脚本
echo "10. 创建管理脚本..."
cat > manage.sh << 'EOF'
#!/bin/bash

# 域名监控服务管理脚本

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR

# 加载环境变量
if [ -f "config.env" ]; then
    export $(cat config.env | grep -v '^#' | grep -v '^$' | xargs)
fi

# 激活虚拟环境
source venv/bin/activate

case "$1" in
    add)
        if [ -z "$2" ]; then
            echo "用法: ./manage.sh add <域名> [备注]"
            exit 1
        fi
        python3 -c "
import json
import sys
from datetime import datetime

domain = '$2'
notes = ' '.join(sys.argv[1:]) if len(sys.argv) > 1 else ''

try:
    with open('domains.json', 'r') as f:
        domains = json.load(f)
except FileNotFoundError:
    domains = {}

if domain in domains:
    print(f'域名 {domain} 已存在')
    exit(1)

domains[domain] = {
    'added_at': datetime.now().isoformat(),
    'last_checked': None,
    'status': 'unknown',
    'notes': notes,
    'notification_sent': False,
    'check_count': 0,
    'error_count': 0
}

with open('domains.json', 'w') as f:
    json.dump(domains, f, ensure_ascii=False, indent=2)

print(f'已添加域名: {domain}')
" "${@:3}"
        ;;
    remove)
        if [ -z "$2" ]; then
            echo "用法: ./manage.sh remove <域名>"
            exit 1
        fi
        python3 -c "
import json

domain = '$2'

try:
    with open('domains.json', 'r') as f:
        domains = json.load(f)
except FileNotFoundError:
    print('域名列表文件不存在')
    exit(1)

if domain in domains:
    del domains[domain]
    with open('domains.json', 'w') as f:
        json.dump(domains, f, ensure_ascii=False, indent=2)
    print(f'已移除域名: {domain}')
else:
    print(f'域名不存在: {domain}')
"
        ;;
    list)
        python3 -c "
import json
from datetime import datetime

try:
    with open('domains.json', 'r') as f:
        domains = json.load(f)
except FileNotFoundError:
    print('域名列表文件不存在')
    exit(1)

if not domains:
    print('没有监控的域名')
else:
    print('监控的域名列表:')
    print('=' * 80)
    for domain, info in domains.items():
        print(f'域名: {domain}')
        print(f'  状态: {info.get(\"status\", \"未知\")}')
        print(f'  添加时间: {info.get(\"added_at\", \"未知\")}')
        if info.get('last_checked'):
            print(f'  最后检查: {info.get(\"last_checked\")}')
        print(f'  检查次数: {info.get(\"check_count\", 0)}')
        print(f'  错误次数: {info.get(\"error_count\", 0)}')
        if info.get('notes'):
            print(f'  备注: {info.get(\"notes\")}')
        print('-' * 80)
"
        ;;
    check)
        echo "开始检查所有域名..."
        python3 -c "
import os
import sys
sys.path.append('.')

try:
    from domain_monitor import DomainMonitor
    monitor = DomainMonitor(
        os.getenv('TELEGRAM_BOT_TOKEN'), 
        os.getenv('TELEGRAM_CHAT_ID')
    )
    monitor.check_all_domains()
    print('检查完成')
except ImportError:
    print('错误: 找不到 domain_monitor.py 文件')
    exit(1)
except Exception as e:
    print(f'检查过程中发生错误: {e}')
    exit(1)
"
        ;;
    status)
        echo "服务状态:"
        sudo supervisorctl status domain-monitor
        echo ""
        echo "最近的日志:"
        tail -n 20 /var/log/domain-monitor/domain-monitor.log 2>/dev/null || echo "日志文件不存在"
        ;;
    logs)
        tail -f /var/log/domain-monitor/domain-monitor.log
        ;;
    restart)
        echo "重启服务..."
        sudo supervisorctl restart domain-monitor
        ;;
    stop)
        echo "停止服务..."
        sudo supervisorctl stop domain-monitor
        ;;
    start)
        echo "启动服务..."
        sudo supervisorctl start domain-monitor
        ;;
    test)
        echo "测试配置..."
        python3 -c "
import os
import sys
sys.path.append('.')

# 测试环境变量
required_vars = ['TELEGRAM_BOT_TOKEN', 'TELEGRAM_CHAT_ID']
missing_vars = []

for var in required_vars:
    if not os.getenv(var):
        missing_vars.append(var)

if missing_vars:
    print(f'缺少必要的环境变量: {missing_vars}')
    exit(1)

# 测试 Telegram 连接
try:
    import requests
    bot_token = os.getenv('TELEGRAM_BOT_TOKEN')
    response = requests.get(f'https://api.telegram.org/bot{bot_token}/getMe', timeout=10)
    if response.status_code == 200:
        print('✓ Telegram Bot 连接正常')
    else:
        print('✗ Telegram Bot 连接失败')
        exit(1)
except Exception as e:
    print(f'✗ Telegram 连接测试失败: {e}')
    exit(1)

print('✓ 配置测试通过')
"
        ;;
    *)
        echo "域名监控服务管理工具"
        echo ""
        echo "用法: ./manage.sh [命令]"
        echo ""
        echo "命令:"
        echo "  add <域名> [备注]  - 添加要监控的域名"
        echo "  remove <域名>      - 移除监控的域名"
        echo "  list              - 列出所有监控的域名"
        echo "  check             - 立即检查所有域名"
        echo "  status            - 查看服务状态"
        echo "  logs              - 查看实时日志"
        echo "  start             - 启动服务"
        echo "  stop              - 停止服务"
        echo "  restart           - 重启服务"
        echo "  test              - 测试配置"
        echo ""
        echo "示例:"
        echo "  ./manage.sh add example.com '重要网站'"
        echo "  ./manage.sh remove example.com"
        echo "  ./manage.sh list"
        ;;
esac
EOF
chmod +x manage.sh

# 创建 Supervisor 配置文件
echo "11. 配置 Supervisor..."
sudo tee /etc/supervisor/conf.d/domain-monitor.conf > /dev/null << EOF
[program:domain-monitor]
command=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/domain_monitor.py
directory=$PROJECT_DIR
user=$USER
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/domain-monitor/domain-monitor.log
stderr_logfile=/var/log/domain-monitor/domain-monitor-error.log
stdout_logfile_maxbytes=10MB
stdout_logfile_backups=5
stderr_logfile_maxbytes=10MB
stderr_logfile_backups=5
environment=PATH="$PROJECT_DIR/venv/bin"
EOF

# 添加环境变量到 supervisor 配置
if [ -f "config.env" ]; then
    echo "environment=PATH=\"$PROJECT_DIR/venv/bin\",$(cat config.env | grep -v '^#' | grep -v '^$' | tr '\n' ',' | sed 's/,$//')" | sudo tee -a /etc/supervisor/conf.d/domain-monitor.conf > /dev/null
fi

# 创建系统服务脚本（可选）
echo "12. 创建系统服务脚本..."
cat > domain-monitor-service.sh << 'EOF'
#!/bin/bash
# 域名监控服务控制脚本

case "$1" in
    install)
        echo "安装系统服务..."
        sudo systemctl enable supervisor
        sudo systemctl start supervisor
        ;;
    uninstall)
        echo "卸载服务..."
        sudo supervisorctl stop domain-monitor
        sudo rm -f /etc/supervisor/conf.d/domain-monitor.conf
        sudo supervisorctl reread
        sudo supervisorctl update
        ;;
    *)
        echo "用法: $0 {install|uninstall}"
        ;;
esac
EOF
chmod +x domain-monitor-service.sh

# 重新加载 Supervisor 配置
echo "13. 启动服务..."
sudo supervisorctl reread
sudo supervisorctl update

# 等待服务启动
sleep 2

# 检查服务状态
SERVICE_STATUS=$(sudo supervisorctl status domain-monitor | awk '{print $2}')
if [ "$SERVICE_STATUS" = "RUNNING" ]; then
    echo "✓ 服务启动成功"
else
    echo "⚠ 服务启动可能有问题，状态: $SERVICE_STATUS"
fi

echo ""
echo "====================================="
echo "部署完成！"
echo "====================================="
echo ""
echo "项目目录: $PROJECT_DIR"
echo "配置文件: $PROJECT_DIR/config.env"
echo "域名列表: $PROJECT_DIR/domains.json"
echo "管理脚本: $PROJECT_DIR/manage.sh"
echo ""
echo "接下来的步骤："
echo "1. 测试配置: cd $PROJECT_DIR && ./manage.sh test"
echo "2. 添加要监控的域名: ./manage.sh add example.com '网站描述'"
echo "3. 查看服务状态: ./manage.sh status"
echo "4. 查看实时日志: ./manage.sh logs"
echo ""
echo "管理命令："
echo "  启动服务: ./manage.sh start"
echo "  停止服务: ./manage.sh stop"
echo "  重启服务: ./manage.sh restart"
echo "  查看状态: ./manage.sh status"
echo "  立即检查: ./manage.sh check"
echo ""
echo "日志文件："
echo "  主日志: /var/log/domain-monitor/domain-monitor.log"
echo "  错误日志: /var/log/domain-monitor/domain-monitor-error.log"
echo ""

# 询问是否立即添加域名
read -p "是否现在添加要监控的域名？(y/N): " add_domain_now
if [[ $add_domain_now =~ ^[Yy]$ ]]; then
    read -p "请输入域名: " domain_to_add
    if [ -n "$domain_to_add" ]; then
        read -p "请输入备注（可选）: " domain_notes
        ./manage.sh add "$domain_to_add" "$domain_notes"
        echo "域名已添加，正在进行首次检查..."
        ./manage.sh check
    fi
fi

echo ""
echo "部署脚本执行完成！"
echo "如有问题，请查看日志文件或运行 './manage.sh test' 进行诊断"
