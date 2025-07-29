#!/bin/bash

# 域名监控服务 VPS 部署脚本
# 支持 Ubuntu/Debian 系统

set -e

echo "====================================="
echo "域名监控服务部署脚本"
echo "====================================="

# 更新系统
echo "1. 更新系统包..."
sudo apt-get update
sudo apt-get upgrade -y

# 安装必要的软件
echo "2. 安装 Python 3 和依赖..."
sudo apt-get install -y python3 python3-pip python3-venv git supervisor

# 创建项目目录
PROJECT_DIR="/opt/domain-monitor"
echo "3. 创建项目目录: $PROJECT_DIR"
sudo mkdir -p $PROJECT_DIR
sudo chown $USER:$USER $PROJECT_DIR
cd $PROJECT_DIR

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
# 这里假设文件已经上传到服务器
# 如果是从 GitHub 克隆，可以使用：
# git clone https://github.com/yourusername/domain-monitor.git .

# 创建配置文件
if [ ! -f "config.env" ]; then
    echo "7. 创建配置文件..."
    cat > config.env << 'EOF'
# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=your_bot_token_here
TELEGRAM_CHAT_ID=your_chat_id_here

# 检查间隔（分钟）
CHECK_INTERVAL_MINUTES=60
EOF
    echo "请编辑 config.env 文件，填入你的 Telegram Bot Token 和 Chat ID"
fi

# 创建域名列表文件
if [ ! -f "domains.json" ]; then
    echo "8. 创建域名列表文件..."
    cat > domains.json << 'EOF'
{}
EOF
fi

# 创建管理脚本
echo "9. 创建管理脚本..."
cat > manage.sh << 'EOF'
#!/bin/bash

# 域名监控服务管理脚本

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
cd $SCRIPT_DIR

# 加载环境变量
if [ -f "config.env" ]; then
    export $(cat config.env | grep -v '^#' | xargs)
fi

case "$1" in
    add)
        if [ -z "$2" ]; then
            echo "用法: ./manage.sh add <域名> [备注]"
            exit 1
        fi
        python3 -c "
import json
domain = '$2'
notes = ' '.join('$@'.split()[2:]) if len('$@'.split()) > 2 else ''
with open('domains.json', 'r') as f:
    domains = json.load(f)
domains[domain] = {
    'added_at': __import__('datetime').datetime.now().isoformat(),
    'last_checked': None,
    'status': 'unknown',
    'notes': notes,
    'notification_sent': False
}
with open('domains.json', 'w') as f:
    json.dump(domains, f, ensure_ascii=False, indent=2)
print(f'已添加域名: {domain}')
"
        ;;
    remove)
        if [ -z "$2" ]; then
            echo "用法: ./manage.sh remove <域名>"
            exit 1
        fi
        python3 -c "
import json
domain = '$2'
with open('domains.json', 'r') as f:
    domains = json.load(f)
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
with open('domains.json', 'r') as f:
    domains = json.load(f)
if not domains:
    print('没有监控的域名')
else:
    print('监控的域名列表:')
    print('-' * 60)
    for domain, info in domains.items():
        print(f'域名: {domain}')
        print(f'  状态: {info.get(\"status\", \"未知\")}')
        print(f'  添加时间: {info.get(\"added_at\", \"未知\")}')
        if info.get('last_checked'):
            print(f'  最后检查: {info.get(\"last_checked\")}')
        if info.get('notes'):
            print(f'  备注: {info.get(\"notes\")}')
        print('-' * 60)
"
        ;;
    check)
        source venv/bin/activate
        python3 -c "
import os
from domain_monitor import DomainMonitor
monitor = DomainMonitor(os.getenv('TELEGRAM_BOT_TOKEN'), os.getenv('TELEGRAM_CHAT_ID'))
monitor.check_all_domains()
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
        ;;
esac
EOF
chmod +x manage.sh

# 创建 Supervisor 配置文件
echo "10. 配置 Supervisor..."
sudo tee /etc/supervisor/conf.d/domain-monitor.conf > /dev/null << EOF
[program:domain-monitor]
command=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/domain_monitor.py
directory=$PROJECT_DIR
user=$USER
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/domain-monitor.log
environment=PATH="$PROJECT_DIR/venv/bin",$(cat $PROJECT_DIR/config.env | grep -v '^#' | xargs -I {} echo '{}' | tr '\n' ',')
EOF

# 重新加载 Supervisor 配置
echo "11. 启动服务..."
sudo supervisorctl reread
sudo supervisorctl update

echo ""
echo "====================================="
echo "部署完成！"
echo "====================================="
echo ""
echo "接下来的步骤："
echo "1. 编辑配置文件: nano $PROJECT_DIR/config.env"
echo "2. 添加要监控的域名: cd $PROJECT_DIR && ./manage.sh add example.com"
echo "3. 查看服务状态: sudo supervisorctl status domain-monitor"
echo "4. 查看日志: tail -f /var/log/domain-monitor.log"
echo ""
echo "管理命令："
echo "  启动服务: sudo supervisorctl start domain-monitor"
echo "  停止服务: sudo supervisorctl stop domain-monitor"
echo "  重启服务: sudo supervisorctl restart domain-monitor"
echo ""
