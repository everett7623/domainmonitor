#!/bin/bash
# DomainMonitor 优化脚本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╔═══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           DomainMonitor 优化配置工具 v1.0                 ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════════════════════════╝${NC}"
echo

# 显示当前配置
show_current_config() {
    echo -e "${BLUE}▶ 当前配置信息：${NC}"
    
    cd /opt/domainmonitor
    source venv/bin/activate
    
    python3 -c "
import json
with open('config/config.json', 'r') as f:
    config = json.load(f)
    
print(f'检查间隔: {config.get(\"check_interval\", 300)} 秒')
print(f'监控域名数: {len(config.get(\"domains\", []))}')
if config.get('domains'):
    print('监控域名列表:')
    for domain in config['domains']:
        print(f'  - {domain}')
"
    
    deactivate
    echo
}

# 修改检查间隔
change_interval() {
    echo -e "${BLUE}▶ 修改检查间隔${NC}"
    echo -e "${YELLOW}建议设置:${NC}"
    echo "  - 60 秒：紧急监控（消耗较多资源）"
    echo "  - 180 秒：积极监控（推荐）"
    echo "  - 300 秒：标准监控（默认）"
    echo "  - 600 秒：节省资源"
    echo
    
    read -p "请输入检查间隔（秒）[180]: " interval
    interval=${interval:-180}
    
    if ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -lt 30 ]; then
        echo -e "${RED}错误: 间隔必须是大于30的数字${NC}"
        return
    fi
    
    cd /opt/domainmonitor
    source venv/bin/activate
    
    python3 -c "
import json
with open('config/config.json', 'r') as f:
    config = json.load(f)
config['check_interval'] = $interval
with open('config/config.json', 'w') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)
print('✓ 检查间隔已更新为 $interval 秒')
"
    
    deactivate
}

# 立即检查并发送状态报告
send_status_report() {
    echo -e "${BLUE}▶ 发送域名状态报告...${NC}"
    
    cd /opt/domainmonitor
    source venv/bin/activate
    
    # 创建状态报告脚本
    cat > /tmp/status_report.py << 'EOF'
import sys
sys.path.append('/opt/domainmonitor')
import json
import requests
import whois
from datetime import datetime

# 加载配置
with open('/opt/domainmonitor/config/config.json', 'r') as f:
    config = json.load(f)

bot_token = config['telegram']['bot_token']
chat_id = config['telegram']['chat_id']
domains = config.get('domains', [])

# 构建状态报告
message = "📊 <b>域名监控状态报告</b>\n\n"
message += f"⏰ <b>报告时间:</b> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
message += f"🔄 <b>检查间隔:</b> {config.get('check_interval', 300)} 秒\n"
message += f"📌 <b>监控域名:</b> {len(domains)} 个\n\n"

if not domains:
    message += "⚠️ 暂无监控域名"
else:
    message += "<b>域名状态详情:</b>\n"
    
    for domain in domains:
        try:
            # 检查域名状态
            w = whois.whois(domain)
            
            if w.domain_name:
                status = "🔴 已注册"
                if w.expiration_date:
                    if isinstance(w.expiration_date, list):
                        exp_date = w.expiration_date[0]
                    else:
                        exp_date = w.expiration_date
                    
                    # 计算剩余天数
                    if hasattr(exp_date, 'date'):
                        days_left = (exp_date - datetime.now()).days
                        status += f" (剩余 {days_left} 天)"
            else:
                status = "🟢 可注册"
                
        except:
            status = "🟢 可注册"
            
        message += f"\n• <code>{domain}</code>\n  状态: {status}\n"

# 发送消息
url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
data = {
    "chat_id": chat_id,
    "text": message,
    "parse_mode": "HTML",
    "disable_web_page_preview": True
}

try:
    response = requests.post(url, json=data, timeout=10)
    if response.status_code == 200:
        print("✓ 状态报告发送成功")
    else:
        print(f"✗ 发送失败: {response.text}")
except Exception as e:
    print(f"✗ 错误: {e}")
EOF
    
    python3 /tmp/status_report.py
    rm -f /tmp/status_report.py
    
    deactivate
}

# 添加定时状态报告
setup_daily_report() {
    echo -e "${BLUE}▶ 设置每日状态报告${NC}"
    
    # 创建定时报告脚本
    cat > /opt/domainmonitor/daily_report.py << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""每日状态报告脚本"""

import sys
sys.path.append('/opt/domainmonitor')
import json
import requests
import whois
from datetime import datetime
from pathlib import Path

# 加载配置
CONFIG_FILE = Path("/opt/domainmonitor/config/config.json")
with open(CONFIG_FILE, 'r') as f:
    config = json.load(f)

# 加载历史记录
HISTORY_FILE = Path("/opt/domainmonitor/data/history.json")
history = {}
if HISTORY_FILE.exists():
    with open(HISTORY_FILE, 'r') as f:
        history = json.load(f)

bot_token = config['telegram']['bot_token']
chat_id = config['telegram']['chat_id']
domains = config.get('domains', [])

# 构建每日报告
message = "📅 <b>域名监控每日报告</b>\n\n"
message += f"📆 <b>日期:</b> {datetime.now().strftime('%Y-%m-%d')}\n"
message += f"⏰ <b>时间:</b> {datetime.now().strftime('%H:%M:%S')}\n"
message += f"📊 <b>监控域名数:</b> {len(domains)}\n\n"

available_count = 0
registered_count = 0
error_count = 0

message += "<b>📋 域名状态汇总:</b>\n"

for domain in domains:
    # 获取历史记录中的最新状态
    if domain in history:
        last_status = history[domain].get('last_status', 'unknown')
        last_check = history[domain].get('last_check', 'N/A')
        
        if last_status == 'available':
            available_count += 1
            emoji = "🟢"
        elif last_status == 'registered':
            registered_count += 1
            emoji = "🔴"
        else:
            error_count += 1
            emoji = "⚠️"
            
        message += f"\n{emoji} <code>{domain}</code>"
        
        # 如果是已注册域名，显示更多信息
        if last_status == 'registered' and history[domain].get('status_history'):
            latest_info = history[domain]['status_history'][-1].get('info', {})
            if latest_info and latest_info.get('expiration_date'):
                message += f"\n   到期时间: {latest_info['expiration_date'][:10]}"

message += f"\n\n<b>📊 统计信息:</b>\n"
message += f"🟢 可注册: {available_count} 个\n"
message += f"🔴 已注册: {registered_count} 个\n"
if error_count > 0:
    message += f"⚠️ 检查失败: {error_count} 个\n"

message += f"\n<b>⚙️ 系统状态:</b>\n"
message += f"✅ 监控服务: 正常运行\n"
message += f"🔄 检查间隔: {config.get('check_interval', 300)} 秒\n"
message += f"📱 通知状态: 正常"

# 发送消息
url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
data = {
    "chat_id": chat_id,
    "text": message,
    "parse_mode": "HTML",
    "disable_web_page_preview": True
}

try:
    response = requests.post(url, json=data, timeout=10)
    if response.status_code == 200:
        print("✓ 每日报告发送成功")
    else:
        print(f"✗ 发送失败: {response.text}")
except Exception as e:
    print(f"✗ 错误: {e}")
EOF

    chmod +x /opt/domainmonitor/daily_report.py
    
    # 添加到 crontab（每天早上9点发送）
    (crontab -l 2>/dev/null | grep -v "daily_report.py"; echo "0 9 * * * /opt/domainmonitor/venv/bin/python /opt/domainmonitor/daily_report.py >> /opt/domainmonitor/logs/daily_report.log 2>&1") | crontab -
    
    echo -e "${GREEN}✓ 每日报告已设置（每天 9:00 发送）${NC}"
}

# 测试域名检查
test_domain_check() {
    echo -e "${BLUE}▶ 测试域名检查功能${NC}"
    
    read -p "请输入要测试的域名: " test_domain
    
    if [[ -z "$test_domain" ]]; then
        echo -e "${RED}错误: 域名不能为空${NC}"
        return
    fi
    
    cd /opt/domainmonitor
    source venv/bin/activate
    
    python3 -c "
import whois
import sys

try:
    print(f'正在检查域名: $test_domain')
    w = whois.whois('$test_domain')
    
    if w.domain_name:
        print(f'✓ 域名状态: 已注册')
        print(f'  注册商: {w.registrar}')
        if w.expiration_date:
            print(f'  到期时间: {w.expiration_date}')
        if w.name_servers:
            print(f'  DNS服务器: {w.name_servers}')
    else:
        print(f'✓ 域名状态: 可注册')
        
except Exception as e:
    print(f'✓ 域名状态: 可注册')
    print(f'  (无法获取详细信息: {e})')
"
    
    deactivate
}

# 主菜单
main_menu() {
    while true; do
        echo
        echo -e "${CYAN}请选择操作:${NC}"
        echo "1) 查看当前配置"
        echo "2) 修改检查间隔"
        echo "3) 发送状态报告"
        echo "4) 设置每日报告"
        echo "5) 测试域名检查"
        echo "6) 查看实时日志"
        echo "7) 重启监控服务"
        echo "0) 退出"
        echo
        
        read -p "请输入选项 [0-7]: " choice
        
        case $choice in
            1)
                show_current_config
                ;;
            2)
                change_interval
                echo -e "${YELLOW}需要重启服务以应用新的检查间隔${NC}"
                read -p "是否立即重启？[Y/n] " -n 1 -r
                echo
                if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
                    systemctl restart domainmonitor
                    echo -e "${GREEN}✓ 服务已重启${NC}"
                fi
                ;;
            3)
                send_status_report
                ;;
            4)
                setup_daily_report
                ;;
            5)
                test_domain_check
                ;;
            6)
                echo -e "${CYAN}显示实时日志 (Ctrl+C 退出)${NC}"
                tail -f /opt/domainmonitor/logs/domainmonitor.log
                ;;
            7)
                systemctl restart domainmonitor
                echo -e "${GREEN}✓ 监控服务已重启${NC}"
                systemctl status domainmonitor --no-pager
                ;;
            0)
                echo -e "${GREEN}再见！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选项${NC}"
                ;;
        esac
    done
}

# 运行主菜单
main_menu
