#!/bin/bash

# ============================================================================
# 域名监控系统 - 管理控制脚本
# 作者: everett7623
# GitHub: https://github.com/everett7623/domainmonitor
# 描述: 域名监控系统的命令行管理工具
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

# 配置
INSTALL_DIR="/opt/domainmonitor"
CONFIG_FILE="$INSTALL_DIR/config.json"
SERVICE_NAME="domainmonitor"
LOG_DIR="/var/log/domainmonitor"
DATA_DIR="$INSTALL_DIR/data"

# 打印带颜色的消息
print_message() {
    echo -e "${2}${1}${NC}"
}

# 打印标题
print_header() {
    echo
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${WHITE}            域名监控系统 - 管理工具 v1.0                 ${CYAN}║${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
}

# 打印分隔线
print_separator() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 检查服务状态
check_status() {
    print_header
    print_message "📊 服务状态" "$CYAN"
    print_separator
    
    if systemctl is-active --quiet $SERVICE_NAME; then
        print_message "✅ 服务状态: 运行中" "$GREEN"
        
        # 显示进程信息
        PID=$(systemctl show -p MainPID --value $SERVICE_NAME)
        print_message "📍 进程 PID: $PID" "$WHITE"
        
        # 显示运行时间
        ACTIVE_TIME=$(systemctl show -p ActiveEnterTimestamp --value $SERVICE_NAME)
        print_message "⏰ 启动时间: $ACTIVE_TIME" "$WHITE"
        
        # 显示内存使用
        if [[ -n "$PID" ]] && [[ "$PID" != "0" ]]; then
            MEM_USAGE=$(ps -o rss= -p $PID | awk '{printf "%.2f MB", $1/1024}')
            print_message "💾 内存使用: $MEM_USAGE" "$WHITE"
        fi
    else
        print_message "❌ 服务状态: 未运行" "$RED"
    fi
    
    echo
    print_message "📁 监控域名" "$CYAN"
    print_separator
    
    # 显示监控的域名数量
    if [[ -f "$CONFIG_FILE" ]]; then
        DOMAIN_COUNT=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    print(len(config.get('domains', [])))
")
        print_message "🌐 监控域名数: $DOMAIN_COUNT" "$WHITE"
    fi
    
    # 显示最近的日志
    echo
    print_message "📄 最近日志" "$CYAN"
    print_separator
    if [[ -f "$LOG_DIR/monitor.log" ]]; then
        tail -n 5 "$LOG_DIR/monitor.log" | while IFS= read -r line; do
            echo -e "${WHITE}$line${NC}"
        done
    else
        print_message "暂无日志" "$YELLOW"
    fi
}

# 添加域名
add_domain() {
    local domain=$1
    
    if [[ -z "$domain" ]]; then
        print_message "❌ 请提供域名" "$RED"
        print_message "用法: domainctl add <domain>" "$YELLOW"
        return 1
    fi
    
    print_message "➕ 添加域名: $domain" "$BLUE"
    
    # 检查域名格式
    if ! echo "$domain" | grep -qP '^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$'; then
        print_message "❌ 无效的域名格式" "$RED"
        return 1
    fi
    
    # 添加到配置文件
    python3 -c "
import json
import sys

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    
    if '$domain' in config.get('domains', []):
        print('域名已存在')
        sys.exit(1)
    
    if 'domains' not in config:
        config['domains'] = []
    
    config['domains'].append('$domain')
    
    with open('$CONFIG_FILE', 'w') as f:
        json.dump(config, f, indent=4)
    
    print('success')
except Exception as e:
    print(f'错误: {e}')
    sys.exit(1)
" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        print_message "✅ 域名添加成功" "$GREEN"
        
        # 重启服务以应用更改
        print_message "🔄 重启服务..." "$BLUE"
        systemctl restart $SERVICE_NAME
        print_message "✅ 服务已重启" "$GREEN"
    else
        print_message "❌ 域名添加失败或已存在" "$RED"
    fi
}

# 删除域名
remove_domain() {
    local domain=$1
    
    if [[ -z "$domain" ]]; then
        print_message "❌ 请提供域名" "$RED"
        print_message "用法: domainctl remove <domain>" "$YELLOW"
        return 1
    fi
    
    print_message "➖ 删除域名: $domain" "$BLUE"
    
    # 从配置文件删除
    python3 -c "
import json
import sys

try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
    
    if '$domain' not in config.get('domains', []):
        print('域名不存在')
        sys.exit(1)
    
    config['domains'].remove('$domain')
    
    with open('$CONFIG_FILE', 'w') as f:
        json.dump(config, f, indent=4)
    
    print('success')
except Exception as e:
    print(f'错误: {e}')
    sys.exit(1)
" 2>/dev/null
    
    if [[ $? -eq 0 ]]; then
        print_message "✅ 域名删除成功" "$GREEN"
        
        # 重启服务
        print_message "🔄 重启服务..." "$BLUE"
        systemctl restart $SERVICE_NAME
        print_message "✅ 服务已重启" "$GREEN"
    else
        print_message "❌ 域名删除失败或不存在" "$RED"
    fi
}

# 列出所有域名
list_domains() {
    print_header
    print_message "📋 监控域名列表" "$CYAN"
    print_separator
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_message "❌ 配置文件不存在" "$RED"
        return 1
    fi
    
    python3 -c "
import json
import os
from datetime import datetime

# 加载配置
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)

domains = config.get('domains', [])

if not domains:
    print('  暂无监控域名')
else:
    # 加载历史记录
    history_file = '$DATA_DIR/domain_history.json'
    history = {}
    if os.path.exists(history_file):
        with open(history_file, 'r') as f:
            history = json.load(f)
    
    # 打印域名列表
    for i, domain in enumerate(domains, 1):
        print(f'  {i}. \033[1;36m{domain}\033[0m')
        
        if domain in history:
            status = history[domain].get('last_status', '未知')
            last_check = history[domain].get('last_check', '从未')
            
            # 状态颜色
            status_color = {
                'available': '\033[0;32m',  # 绿色
                'registered': '\033[0;31m',  # 红色
                'unknown': '\033[1;33m'      # 黄色
            }.get(status, '\033[0m')
            
            # 格式化时间
            if last_check != '从未':
                try:
                    dt = datetime.fromisoformat(last_check)
                    last_check = dt.strftime('%Y-%m-%d %H:%M:%S')
                except:
                    pass
            
            print(f'     状态: {status_color}{status}\033[0m')
            print(f'     最后检查: {last_check}')
        else:
            print('     状态: \033[1;33m未检查\033[0m')
        print()
"
    
    # 显示统计信息
    echo
    print_message "📊 统计信息" "$CYAN"
    print_separator
    
    TOTAL=$(python3 -c "
import json
with open('$CONFIG_FILE') as f:
    config = json.load(f)
    print(len(config.get('domains', [])))
")
    
    AVAILABLE=$(python3 -c "
import json
import os

history_file = '$DATA_DIR/domain_history.json'
if os.path.exists(history_file):
    with open(history_file) as f:
        history = json.load(f)
        available = sum(1 for d in history.values() if d.get('last_status') == 'available')
        print(available)
else:
    print(0)
" 2>/dev/null || echo "0")
    
    REGISTERED=$(python3 -c "
import json
import os

history_file = '$DATA_DIR/domain_history.json'
if os.path.exists(history_file):
    with open(history_file) as f:
        history = json.load(f)
        registered = sum(1 for d in history.values() if d.get('last_status') == 'registered')
        print(registered)
else:
    print(0)
" 2>/dev/null || echo "0")
    
    print_message "  📝 总计: $TOTAL 个域名" "$WHITE"
    print_message "  🟢 可注册: $AVAILABLE 个" "$GREEN"
    print_message "  🔴 已注册: $REGISTERED 个" "$RED"
}

# 查看日志
view_logs() {
    local lines=${1:-50}
    
    print_header
    print_message "📄 查看日志 (最近 $lines 行)" "$CYAN"
    print_separator
    
    if [[ -f "$LOG_DIR/monitor.log" ]]; then
        tail -n "$lines" "$LOG_DIR/monitor.log" | while IFS= read -r line; do
            # 根据日志级别着色
            if echo "$line" | grep -q "ERROR"; then
                echo -e "${RED}$line${NC}"
            elif echo "$line" | grep -q "WARNING"; then
                echo -e "${YELLOW}$line${NC}"
            elif echo "$line" | grep -q "INFO"; then
                echo -e "${WHITE}$line${NC}"
            else
                echo -e "$line"
            fi
        done
    else
        print_message "暂无日志文件" "$YELLOW"
    fi
}

# 实时查看日志
follow_logs() {
    print_header
    print_message "📄 实时日志 (按 Ctrl+C 退出)" "$CYAN"
    print_separator
    
    if [[ -f "$LOG_DIR/monitor.log" ]]; then
        tail -f "$LOG_DIR/monitor.log"
    else
        print_message "暂无日志文件" "$YELLOW"
    fi
}

# 配置Telegram
config_telegram() {
    print_header
    print_message "🤖 配置Telegram通知" "$CYAN"
    print_separator
    
    read -p "$(echo -e ${WHITE}"请输入Bot Token: "${NC})" BOT_TOKEN
    read -p "$(echo -e ${WHITE}"请输入Chat ID: "${NC})" CHAT_ID
    
    python3 -c "
import json

with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)

config['telegram'] = {
    'bot_token': '$BOT_TOKEN',
    'chat_id': '$CHAT_ID',
    'enabled': True
}

with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=4)
"
    
    print_message "✅ Telegram配置已更新" "$GREEN"
    
    # 重启服务
    print_message "🔄 重启服务..." "$BLUE"
    systemctl restart $SERVICE_NAME
    print_message "✅ 服务已重启" "$GREEN"
}

# 测试通知
test_notification() {
    print_header
    print_message "🧪 测试Telegram通知" "$CYAN"
    print_separator
    
    python3 -c "
import json
import requests
from datetime import datetime

with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)

if not config.get('telegram', {}).get('enabled'):
    print('❌ Telegram通知未启用')
    exit(1)

bot_token = config['telegram']['bot_token']
chat_id = config['telegram']['chat_id']

message = f'''
🧪 <b>测试通知</b> 🧪

这是一条来自域名监控系统的测试消息
时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

如果您收到这条消息，说明通知配置正确！
'''

api_url = f'https://api.telegram.org/bot{bot_token}/sendMessage'
data = {
    'chat_id': chat_id,
    'text': message,
    'parse_mode': 'HTML'
}

response = requests.post(api_url, json=data)
if response.status_code == 200:
    print('✅ 测试通知发送成功')
else:
    print(f'❌ 发送失败: {response.text}')
"
}

# 立即检查所有域名
check_now() {
    print_header
    print_message "🔍 立即检查所有域名" "$CYAN"
    print_separator
    
    print_message "📡 触发域名检查..." "$BLUE"
    
    # 创建临时Python脚本进行单次检查
    cat > /tmp/check_domains.py << 'EOF'
#!/usr/bin/env python3
import sys
sys.path.insert(0, '/opt/domainmonitor')
from domain_monitor import DomainMonitor
monitor = DomainMonitor()
monitor.check_all_domains()
EOF
    
    chmod +x /tmp/check_domains.py
    
    # 执行检查
    cd /opt/domainmonitor
    python3 /tmp/check_domains.py
    
    rm -f /tmp/check_domains.py
    
    print_message "✅ 域名检查完成" "$GREEN"
    echo
    print_message "💡 提示：" "$YELLOW"
    print_message "  • 如果域名可注册，您会收到Telegram通知" "$WHITE"
    print_message "  • 查看详细日志: domainctl logs" "$WHITE"
    print_message "  • 查看域名状态: domainctl list" "$WHITE"
}

# 显示帮助
show_help() {
    print_header
    print_message "📚 使用帮助" "$CYAN"
    print_separator
    
    echo -e "${WHITE}基础命令:${NC}"
    echo -e "  ${YELLOW}status${NC}              查看服务状态"
    echo -e "  ${YELLOW}start${NC}               启动服务"
    echo -e "  ${YELLOW}stop${NC}                停止服务"
    echo -e "  ${YELLOW}restart${NC}             重启服务"
    echo
    echo -e "${WHITE}域名管理:${NC}"
    echo -e "  ${YELLOW}add <domain>${NC}        添加监控域名"
    echo -e "  ${YELLOW}remove <domain>${NC}     删除监控域名"
    echo -e "  ${YELLOW}list${NC}                列出所有域名"
    echo -e "  ${YELLOW}check${NC}               立即检查所有域名"
    echo -e "  ${YELLOW}reset${NC}               重置通知状态"
    echo
    echo -e "${WHITE}日志查看:${NC}"
    echo -e "  ${YELLOW}logs [lines]${NC}        查看日志 (默认50行)"
    echo -e "  ${YELLOW}follow${NC}              实时查看日志"
    echo
    echo -e "${WHITE}配置管理:${NC}"
    echo -e "  ${YELLOW}config telegram${NC}     配置Telegram通知"
    echo -e "  ${YELLOW}test${NC}                测试通知发送"
    echo
    echo -e "${WHITE}其他命令:${NC}"
    echo -e "  ${YELLOW}update${NC}              更新监控系统"
    echo -e "  ${YELLOW}uninstall${NC}           卸载监控系统"
    echo -e "  ${YELLOW}help${NC}                显示此帮助"
    echo
    print_separator
    echo -e "${CYAN}示例:${NC}"
    echo -e "  ${WHITE}domainctl add example.com${NC}"
    echo -e "  ${WHITE}domainctl remove example.com${NC}"
    echo -e "  ${WHITE}domainctl logs 100${NC}"
    echo -e "  ${WHITE}domainctl check${NC}"
}

# 更新系统
update_system() {
    print_header
    print_message "🔄 更新域名监控系统" "$CYAN"
    print_separator
    
    print_message "⬇️ 下载最新版本..." "$BLUE"
    
    # 备份当前配置
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup"
    
    # 下载新版本
    wget -q -O /tmp/domain_monitor.py https://raw.githubusercontent.com/everett7623/domainmonitor/main/domain_monitor.py
    wget -q -O /tmp/domainctl.sh https://raw.githubusercontent.com/everett7623/domainmonitor/main/domainctl.sh
    
    if [[ $? -eq 0 ]]; then
        # 停止服务
        systemctl stop $SERVICE_NAME
        
        # 更新文件
        mv /tmp/domain_monitor.py "$INSTALL_DIR/domain_monitor.py"
        mv /tmp/domainctl.sh "$INSTALL_DIR/domainctl.sh"
        chmod +x "$INSTALL_DIR/domain_monitor.py"
        chmod +x "$INSTALL_DIR/domainctl.sh"
        
        # 重启服务
        systemctl start $SERVICE_NAME
        
        print_message "✅ 更新完成" "$GREEN"
    else
        print_message "❌ 更新失败" "$RED"
        # 恢复配置
        mv "$CONFIG_FILE.backup" "$CONFIG_FILE"
    fi
}

# 卸载系统
uninstall_system() {
    print_header
    print_message "⚠️  卸载域名监控系统" "$YELLOW"
    print_separator
    
    read -p "$(echo -e ${RED}"确定要卸载吗？这将删除所有数据 (y/N): "${NC})" CONFIRM
    
    if [[ "$CONFIRM" == "y" ]] || [[ "$CONFIRM" == "Y" ]]; then
        print_message "🗑️ 开始卸载..." "$BLUE"
        
        # 停止并禁用服务
        systemctl stop $SERVICE_NAME
        systemctl disable $SERVICE_NAME
        rm -f /etc/systemd/system/${SERVICE_NAME}.service
        
        # 删除文件
        rm -rf "$INSTALL_DIR"
        rm -rf "$LOG_DIR"
        rm -f /usr/local/bin/domainctl
        
        print_message "✅ 卸载完成" "$GREEN"
    else
        print_message "❌ 卸载已取消" "$YELLOW"
    fi
}

# 重置通知状态
reset_notifications() {
    print_header
    print_message "🔄 重置通知状态" "$CYAN"
    print_separator
    
    print_message "📝 此操作将重置所有域名的通知状态" "$YELLOW"
    print_message "   可以重新接收已发送过的通知" "$YELLOW"
    echo
    
    read -p "$(echo -e ${WHITE}"确定要重置吗？(y/N): "${NC})" CONFIRM
    
    if [[ "$CONFIRM" == "y" ]] || [[ "$CONFIRM" == "Y" ]]; then
        # 重置历史文件中的通知标记
        python3 -c "
import json
import os

history_file = '$DATA_DIR/domain_history.json'
if os.path.exists(history_file):
    with open(history_file, 'r') as f:
        history = json.load(f)
    
    for domain in history:
        history[domain]['notification_sent'] = False
    
    with open(history_file, 'w') as f:
        json.dump(history, f, indent=4)
    
    print('✅ 通知状态已重置')
else:
    print('⚠️ 暂无历史记录')
"
        print_message "✅ 重置完成，下次检查时会重新发送通知" "$GREEN"
    else
        print_message "❌ 操作已取消" "$YELLOW"
    fi
}

# 主函数
main() {
    case "$1" in
        status)
            check_status
            ;;
        start)
            systemctl start $SERVICE_NAME
            print_message "✅ 服务已启动" "$GREEN"
            ;;
        stop)
            systemctl stop $SERVICE_NAME
            print_message "⏹️ 服务已停止" "$YELLOW"
            ;;
        restart)
            systemctl restart $SERVICE_NAME
            print_message "🔄 服务已重启" "$GREEN"
            ;;
        add)
            add_domain "$2"
            ;;
        remove|rm|delete|del)
            remove_domain "$2"
            ;;
        list|ls)
            list_domains
            ;;
        logs|log)
            view_logs "${2:-50}"
            ;;
        follow|tail)
            follow_logs
            ;;
        config)
            if [[ "$2" == "telegram" ]]; then
                config_telegram
            else
                print_message "用法: domainctl config telegram" "$YELLOW"
            fi
            ;;
        test)
            test_notification
            ;;
        check)
            check_now
            ;;
        reset)
            reset_notifications
            ;;
        update)
            update_system
            ;;
        uninstall)
            uninstall_system
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            if [[ -z "$1" ]]; then
                check_status
            else
                print_message "❌ 未知命令: $1" "$RED"
                echo
                show_help
            fi
            ;;
    esac
}

# 运行主函数
main "$@"
