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
        # 使用 Python 脚本添加域名，避免 shell 参数处理问题
        python3 << EOF
import json
import sys
from datetime import datetime

domain = "$2"
# 获取所有参数作为备注
import subprocess
result = subprocess.run(['echo'] + sys.argv[3:], capture_output=True, text=True)
notes = ""
# 如果有第三个参数，将其作为备注
if len(sys.argv) > 3:
    notes = "$3"
    
try:
    with open('domains.json', 'r') as f:
        domains = json.load(f)
except:
    domains = {}

domains[domain] = {
    'added_at': datetime.now().isoformat(),
    'last_checked': None,
    'status': 'unknown',
    'notes': notes,
    'notification_sent': False
}

with open('domains.json', 'w') as f:
    json.dump(domains, f, ensure_ascii=False, indent=2)
    
print(f'已添加域名: {domain}')
if notes:
    print(f'备注: {notes}')
EOF
        ;;
    remove)
        if [ -z "$2" ]; then
            echo "用法: ./manage.sh remove <域名>"
            exit 1
        fi
        python3 << EOF
import json

domain = "$2"
try:
    with open('domains.json', 'r') as f:
        domains = json.load(f)
    
    if domain in domains:
        del domains[domain]
        with open('domains.json', 'w') as f:
            json.dump(domains, f, ensure_ascii=False, indent=2)
        print(f'已移除域名: {domain}')
    else:
        print(f'域名不存在: {domain}')
except Exception as e:
    print(f'错误: {e}')
EOF
        ;;
    list)
        python3 << EOF
import json
from datetime import datetime

try:
    with open('domains.json', 'r') as f:
        domains = json.load(f)
    
    if not domains:
        print('没有监控的域名')
    else:
        print('监控的域名列表:')
        print('-' * 60)
        for domain, info in domains.items():
            print(f'域名: {domain}')
            print(f'  状态: {info.get("status", "未知")}')
            print(f'  添加时间: {info.get("added_at", "未知")}')
            if info.get('last_checked'):
                print(f'  最后检查: {info.get("last_checked")}')
            if info.get('notes'):
                print(f'  备注: {info.get("notes")}')
            print('-' * 60)
except Exception as e:
    print(f'错误: {e}')
EOF
        ;;
    check)
        source venv/bin/activate
        python3 << EOF
import os
import sys
sys.path.append('$SCRIPT_DIR')
from domain_monitor import DomainMonitor

try:
    monitor = DomainMonitor(
        os.getenv('TELEGRAM_BOT_TOKEN'), 
        os.getenv('TELEGRAM_CHAT_ID')
    )
    monitor.check_all_domains()
except Exception as e:
    print(f'错误: {e}')
    print('请确保已正确配置 Telegram Bot')
EOF
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
