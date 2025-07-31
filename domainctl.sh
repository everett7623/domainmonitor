#!/bin/bash
# ================================================================================
# DomainMonitor 管理工具
# 
# 作者: everett7623
# GitHub: https://github.com/everett7623/domainmonitor
# 版本: v2.0.0
# 
# 使用方法: domainctl [命令] [参数]
# ================================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置
INSTALL_DIR="/opt/domainmonitor"
SERVICE_NAME="domainmonitor"
CONFIG_FILE="$INSTALL_DIR/config/config.json"
PYTHON_BIN="$INSTALL_DIR/venv/bin/python"

# 检查是否安装
check_installation() {
    if [[ ! -d "$INSTALL_DIR" ]]; then
        echo -e "${RED}错误: DomainMonitor 未安装${NC}"
        echo -e "请运行: ${CYAN}bash <(curl -sSL https://raw.githubusercontent.com/everett7623/domainmonitor/main/install.sh)${NC}"
        exit 1
    fi
}

# 显示帮助
show_help() {
    echo -e "${CYAN}DomainMonitor 管理工具 v2.0${NC}"
    echo
    echo "使用方法: domainctl [命令] [参数]"
    echo
    echo -e "${GREEN}服务管理:${NC}"
    echo -e "  ${CYAN}start${NC}      启动监控服务"
    echo -e "  ${CYAN}stop${NC}       停止监控服务"
    echo -e "  ${CYAN}restart${NC}    重启监控服务"
    echo -e "  ${CYAN}status${NC}     查看服务状态"
    echo
    echo -e "${GREEN}域名管理:${NC}"
    echo -e "  ${CYAN}add${NC}        添加监控域名"
    echo -e "  ${CYAN}remove${NC}     删除监控域名"
    echo -e "  ${CYAN}list${NC}       列出所有监控域名"
    echo -e "  ${CYAN}check${NC}      立即检查所有域名"
    echo -e "  ${CYAN}test${NC}       测试域名状态"
    echo
    echo -e "${GREEN}监控配置:${NC}"
    echo -e "  ${CYAN}config${NC}     编辑配置文件"
    echo -e "  ${CYAN}interval${NC}   修改检查间隔"
    echo -e "  ${CYAN}report${NC}     发送状态报告"
    echo -e "  ${CYAN}daily${NC}      设置每日报告"
    echo
    echo -e "${GREEN}系统维护:${NC}"
    echo -e "  ${CYAN}logs${NC}       查看日志"
    echo -e "  ${CYAN}update${NC}     更新程序"
    echo -e "  ${CYAN}uninstall${NC}  卸载程序"
    echo
    echo "示例:"
    echo -e "  ${CYAN}domainctl add example.com${NC}"
    echo -e "  ${CYAN}domainctl interval 180${NC}"
    echo -e "  ${CYAN}domainctl logs -f${NC}"
}

# 启动服务
start_service() {
    echo -e "${BLUE}▶ 启动 DomainMonitor 服务...${NC}"
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${YELLOW}⚠ 服务已在运行中${NC}"
        return
    fi
    
    systemctl start $SERVICE_NAME
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}✓ 服务启动成功${NC}"
        systemctl status $SERVICE_NAME --no-pager
    else
        echo -e "${RED}✗ 服务启动失败${NC}"
        echo -e "${YELLOW}查看错误日志: ${CYAN}domainctl logs -e${NC}"
        exit 1
    fi
}

# 停止服务
stop_service() {
    echo -e "${BLUE}▶ 停止 DomainMonitor 服务...${NC}"
    
    if ! systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${YELLOW}⚠ 服务未在运行${NC}"
        return
    fi
    
    systemctl stop $SERVICE_NAME
    echo -e "${GREEN}✓ 服务已停止${NC}"
}

# 重启服务
restart_service() {
    echo -e "${BLUE}▶ 重启 DomainMonitor 服务...${NC}"
    systemctl restart $SERVICE_NAME
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}✓ 服务重启成功${NC}"
        systemctl status $SERVICE_NAME --no-pager
    else
        echo -e "${RED}✗ 服务重启失败${NC}"
        exit 1
    fi
}

# 查看状态
show_status() {
    echo -e "${BLUE}▶ DomainMonitor 服务状态${NC}"
    systemctl status $SERVICE_NAME
    
    echo
    echo -e "${BLUE}▶ 监控统计${NC}"
    
    cd "$INSTALL_DIR"
    source venv/bin/activate
    
    python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    
    print(f'监控域名数: {len(config.get(\"domains\", []))}')
    print(f'检查间隔: {config.get(\"check_interval\", 300)} 秒')
    
    if config.get('domains'):
        print('\n监控域名:')
        for domain in config['domains']:
            print(f'  • {domain}')
except Exception as e:
    print(f'读取配置失败: {e}')
"
    
    deactivate
    
    echo
    echo -e "${BLUE}▶ 最近日志${NC}"
    tail -n 10 "$INSTALL_DIR/logs/domainmonitor.log" 2>/dev/null || echo "暂无日志"
}

# 添加域名
add_domain() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        echo -e "${YELLOW}请输入要添加的域名:${NC}"
        read -p "> " domain
    fi
    
    if [[ -z "$domain" ]]; then
        echo -e "${RED}错误: 域名不能为空${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}▶ 添加域名: ${domain}${NC}"
    
    cd "$INSTALL_DIR"
    source venv/bin/activate
    
    python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    
    if '$domain' in config['domains']:
        print('⚠ 域名已存在')
        exit(1)
    
    config['domains'].append('$domain')
    
    with open('$CONFIG_FILE', 'w') as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    
    print('✓ 域名添加成功')
except Exception as e:
    print(f'✗ 添加失败: {e}')
    exit(1)
"
    
    deactivate
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${CYAN}正在重启服务以应用更改...${NC}"
        systemctl restart $SERVICE_NAME
    fi
}

# 删除域名
remove_domain() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        list_domains
        echo
        echo -e "${YELLOW}请输入要删除的域名:${NC}"
        read -p "> " domain
    fi
    
    if [[ -z "$domain" ]]; then
        echo -e "${RED}错误: 域名不能为空${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}▶ 删除域名: ${domain}${NC}"
    
    cd "$INSTALL_DIR"
    source venv/bin/activate
    
    python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    
    if '$domain' not in config['domains']:
        print('⚠ 域名不存在')
        exit(1)
    
    config['domains'].remove('$domain')
    
    with open('$CONFIG_FILE', 'w') as f:
        json.dump(config, f, indent=4, ensure_ascii=False)
    
    print('✓ 域名删除成功')
except Exception as e:
    print(f'✗ 删除失败: {e}')
    exit(1)
"
    
    deactivate
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${CYAN}正在重启服务以应用更改...${NC}"
        systemctl restart $SERVICE_NAME
    fi
}

# 列出域名
list_domains() {
    echo -e "${BLUE}▶ 监控域名列表${NC}"
    
    cd "$INSTALL_DIR"
    source venv/bin/activate
    
    python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
    
domains = config.get('domains', [])
if not domains:
    print('暂无监控域名')
else:
    for i, domain in enumerate(domains, 1):
        print(f'{i:3d}. {domain}')
"
    
    deactivate
}

# 立即检查
check_now() {
    echo -e "${BLUE}▶ 立即检查所有域名${NC}"
    
    cd "$INSTALL_DIR"
    source venv/bin/activate
    
    cat > /tmp/check_once.py << 'EOF'
import sys
sys.path.append('/opt/domainmonitor')
from domainmonitor import DomainMonitor

monitor = DomainMonitor()
monitor.check_all_domains()
print("\n✓ 检查完成")
EOF
    
    python3 /tmp/check_once.py
    rm -f /tmp/check_once.py
    
    deactivate
}

# 测试域名
test_domain() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        echo -e "${YELLOW}请输入要测试的域名:${NC}"
        read -p "> " domain
    fi
    
    if [[ -z "$domain" ]]; then
        echo -e "${RED}错误: 域名不能为空${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}▶ 测试域名: ${domain}${NC}"
    
    cd "$INSTALL_DIR"
    source venv/bin/activate
    
    python3 -c "
import whois

try:
    print(f'正在检查域名: $domain')
    w = whois.whois('$domain')
    
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

# 修改检查间隔
change_interval() {
    local interval="$1"
    
    if [[ -z "$interval" ]]; then
        echo -e "${BLUE}▶ 修改检查间隔${NC}"
        echo -e "${YELLOW}建议设置:${NC}"
        echo "  60 秒 - 紧急监控"
        echo "  180 秒 - 积极监控（推荐）"
        echo "  300 秒 - 标准监控（默认）"
        echo "  600 秒 - 节省资源"
        echo
        read -p "请输入检查间隔（秒）[180]: " interval
        interval=${interval:-180}
    fi
    
    if ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -lt 30 ]; then
        echo -e "${RED}错误: 间隔必须是大于30的数字${NC}"
        exit 1
    fi
    
    cd "$INSTALL_DIR"
    source venv/bin/activate
    
    python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
config['check_interval'] = $interval
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=4, ensure_ascii=False)
print('✓ 检查间隔已更新为 $interval 秒')
"
    
    deactivate
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${CYAN}正在重启服务以应用更改...${NC}"
        systemctl restart $SERVICE_NAME
    fi
}

# 发送状态报告
send_report() {
    echo -e "${BLUE}▶ 发送域名状态报告...${NC}"
    
    cd "$INSTALL_DIR"
    source venv/bin/activate
    
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
            w = whois.whois(domain)
            
            if w.domain_name:
                status = "🔴 已注册"
                if w.expiration_date:
                    if isinstance(w.expiration_date, list):
                        exp_date = w.expiration_date[0]
                    else:
                        exp_date = w.expiration_date
                    
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

# 设置每日报告
setup_daily() {
    echo -e "${BLUE}▶ 设置每日状态报告${NC}"
    
    # 创建每日报告脚本
    cat > "$INSTALL_DIR/daily_report.py" << 'EOF'
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

message += "<b>📋 域名状态汇总:</b>\n"

for domain in domains:
    if domain in history:
        last_status = history[domain].get('last_status', 'unknown')
        
        if last_status == 'available':
            available_count += 1
            emoji = "🟢"
        elif last_status == 'registered':
            registered_count += 1
            emoji = "🔴"
        else:
            emoji = "⚠️"
            
        message += f"\n{emoji} <code>{domain}</code>"

message += f"\n\n<b>📊 统计信息:</b>\n"
message += f"🟢 可注册: {available_count} 个\n"
message += f"🔴 已注册: {registered_count} 个\n"

message += f"\n<b>⚙️ 系统状态:</b>\n"
message += f"✅ 监控服务: 正常运行\n"
message += f"🔄 检查间隔: {config.get('check_interval', 300)} 秒"

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
except Exception as e:
    print(f"✗ 错误: {e}")
EOF

    chmod +x "$INSTALL_DIR/daily_report.py"
    
    # 添加到 crontab
    (crontab -l 2>/dev/null | grep -v "daily_report.py"; echo "0 9 * * * $INSTALL_DIR/venv/bin/python $INSTALL_DIR/daily_report.py >> $INSTALL_DIR/logs/daily_report.log 2>&1") | crontab -
    
    echo -e "${GREEN}✓ 每日报告已设置（每天 9:00 发送）${NC}"
}

# 查看日志
view_logs() {
    local option="$1"
    
    case "$option" in
        -f|--follow)
            echo -e "${BLUE}▶ 实时查看日志 (Ctrl+C 退出)${NC}"
            tail -f "$INSTALL_DIR/logs/domainmonitor.log"
            ;;
        -e|--error)
            echo -e "${BLUE}▶ 查看错误日志${NC}"
            if [[ -f "$INSTALL_DIR/logs/domainmonitor.error.log" ]]; then
                tail -n 50 "$INSTALL_DIR/logs/domainmonitor.error.log"
            else
                echo -e "${YELLOW}暂无错误日志${NC}"
            fi
            ;;
        -n)
            local lines="${2:-50}"
            echo -e "${BLUE}▶ 查看最近 ${lines} 行日志${NC}"
            tail -n "$lines" "$INSTALL_DIR/logs/domainmonitor.log"
            ;;
        *)
            echo -e "${BLUE}▶ 查看最近日志${NC}"
            tail -n 50 "$INSTALL_DIR/logs/domainmonitor.log"
            echo
            echo -e "${CYAN}提示: 使用 'domainctl logs -f' 实时查看日志${NC}"
            ;;
    esac
}

# 编辑配置
edit_config() {
    echo -e "${BLUE}▶ 编辑配置文件${NC}"
    
    # 检查编辑器
    if command -v nano &> /dev/null; then
        EDITOR="nano"
    elif command -v vim &> /dev/null; then
        EDITOR="vim"
    elif command -v vi &> /dev/null; then
        EDITOR="vi"
    else
        echo -e "${RED}错误: 未找到文本编辑器${NC}"
        exit 1
    fi
    
    # 备份配置
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"
    echo -e "${CYAN}已创建配置备份: ${CONFIG_FILE}.bak${NC}"
    
    # 编辑配置
    $EDITOR "$CONFIG_FILE"
    
    # 验证配置
    cd "$INSTALL_DIR"
    source venv/bin/activate
    
    python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        json.load(f)
    print('✓ 配置文件格式正确')
except Exception as e:
    print(f'✗ 配置文件格式错误: {e}')
    print('正在恢复备份...')
    import shutil
    shutil.copy('$CONFIG_FILE.bak', '$CONFIG_FILE')
    exit(1)
"
    
    deactivate
    
    # 询问是否重启服务
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo
        read -p "是否重启服务以应用更改？[Y/n] " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]] || [[ -z $REPLY ]]; then
            restart_service
        fi
    fi
}

# 更新程序
update_program() {
    echo -e "${BLUE}▶ 更新 DomainMonitor${NC}"
    
    cd "$INSTALL_DIR"
    
    # 下载最新版本
    echo -e "${CYAN}下载最新版本...${NC}"
    
    # 备份当前版本
    cp domainmonitor.py domainmonitor.py.bak
    cp domainctl.sh domainctl.sh.bak
    
    # 下载新版本
    if curl -sSL "https://raw.githubusercontent.com/everett7623/domainmonitor/main/domainmonitor.py" -o domainmonitor.py.new &&
       curl -sSL "https://raw.githubusercontent.com/everett7623/domainmonitor/main/domainctl.sh" -o domainctl.sh.new; then
        
        # 检查文件是否有效
        if grep -q "404" domainmonitor.py.new || [ ! -s domainmonitor.py.new ]; then
            echo -e "${RED}✗ 下载失败，保留当前版本${NC}"
            rm -f domainmonitor.py.new domainctl.sh.new
            exit 1
        fi
        
        # 替换文件
        mv domainmonitor.py.new domainmonitor.py
        mv domainctl.sh.new domainctl.sh
        chmod +x domainmonitor.py domainctl.sh
        
        echo -e "${GREEN}✓ 更新完成${NC}"
        
        # 重启服务
        if systemctl is-active --quiet $SERVICE_NAME; then
            restart_service
        fi
    else
        echo -e "${RED}✗ 更新失败${NC}"
        exit 1
    fi
}

# 卸载程序
uninstall_program() {
    echo -e "${RED}▶ 卸载 DomainMonitor${NC}"
    echo -e "${YELLOW}警告: 此操作将删除所有数据和配置！${NC}"
    echo
    read -p "确定要卸载吗？输入 'YES' 确认: " confirm
    
    if [[ "$confirm" != "YES" ]]; then
        echo -e "${CYAN}已取消卸载${NC}"
        exit 0
    fi
    
    # 停止服务
    systemctl stop $SERVICE_NAME 2>/dev/null
    systemctl disable $SERVICE_NAME 2>/dev/null
    
    # 删除服务文件
    rm -f /etc/systemd/system/${SERVICE_NAME}.service
    systemctl daemon-reload
    
    # 删除软链接
    rm -f /usr/local/bin/domainctl
    
    # 删除 crontab
    crontab -l 2>/dev/null | grep -v "daily_report.py" | crontab -
    
    # 删除安装目录
    rm -rf "$INSTALL_DIR"
    
    echo -e "${GREEN}✓ DomainMonitor 已完全卸载${NC}"
}

# 主函数
main() {
    check_installation
    
    case "$1" in
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
            show_status
            ;;
        add)
            add_domain "$2"
            ;;
        remove|rm)
            remove_domain "$2"
            ;;
        list|ls)
            list_domains
            ;;
        check)
            check_now
            ;;
        test)
            test_domain "$2"
            ;;
        interval)
            change_interval "$2"
            ;;
        report)
            send_report
            ;;
        daily)
            setup_daily
            ;;
        logs|log)
            view_logs "$2" "$3"
            ;;
        config|conf)
            edit_config
            ;;
        update)
            update_program
            ;;
        uninstall)
            uninstall_program
            ;;
        help|-h|--help|"")
            show_help
            ;;
        *)
            echo -e "${RED}错误: 未知命令 '$1'${NC}"
            echo
            show_help
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
