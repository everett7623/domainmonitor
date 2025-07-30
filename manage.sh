#!/bin/bash
# ==============================================================================
# 域名监控系统管理脚本
# 项目: https://github.com/everett7623/domainmonitor
# 功能: 提供友好的命令行界面管理域名监控
# 作者: everett7623
# 版本: 2.0.0
# ==============================================================================

INSTALL_DIR="/opt/domainmonitor"
CONFIG_FILE="$INSTALL_DIR/config.json"
DOMAINS_FILE="$INSTALL_DIR/domains.txt"
SERVICE_NAME="domainmonitor"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${PURPLE}"
    cat << 'EOF'
  ____                  __  __             _ __            
 |  _ \  ___  _ __ ___ |  \/  | ___  _ __ (_) |_ ___  _ __
 | | | |/ _ \| '_ ` _ \| |\/| |/ _ \| '_ \| | __/ _ \| '__|
 | |_| | (_) | | | | | | |  | | (_) | | | | | || (_) | |   
 |____/ \___/|_| |_| |_|_|  |_|\___/|_| |_|_|\__\___/|_|   
                                                           
EOF
    echo -e "${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        域名监控管理系统 v2.0          ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}1.${NC} 添加监控域名"
    echo -e "${GREEN}2.${NC} 删除监控域名"
    echo -e "${GREEN}3.${NC} 配置Telegram Bot通知"
    echo -e "${GREEN}4.${NC} 删除Telegram Bot通知"
    echo -e "${GREEN}5.${NC} 查看监控域名列表"
    echo -e "${GREEN}6.${NC} 查看服务状态"
    echo -e "${GREEN}7.${NC} 重启监控服务"
    echo -e "${GREEN}8.${NC} 查看运行日志"
    echo -e "${GREEN}9.${NC} 立即检查所有域名"
    echo -e "${GREEN}10.${NC} 修改检查间隔"
    echo -e "${GREEN}11.${NC} 查看检查历史"
    echo -e "${GREEN}12.${NC} 高级设置"
    echo -e "${GREEN}13.${NC} 卸载监控系统"
    echo -e "${GREEN}0.${NC} 退出"
    echo -e "${BLUE}========================================${NC}"
}

# 验证域名格式
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

add_domain() {
    echo -e "${BLUE}添加监控域名${NC}"
    echo -e "${CYAN}提示: 可以一次输入多个域名，用空格分隔${NC}"
    read -p "请输入要监控的域名: " domains
    
    if [[ -z "$domains" ]]; then
        echo -e "${RED}域名不能为空${NC}"
        return
    fi
    
    added_count=0
    duplicate_count=0
    invalid_count=0
    
    for domain in $domains; do
        # 转换为小写
        domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
        
        # 验证域名格式
        if ! validate_domain "$domain"; then
            echo -e "${RED}✗ 无效的域名格式: $domain${NC}"
            ((invalid_count++))
            continue
        fi
        
        # 检查域名是否已存在
        if grep -q "^$domain$" "$DOMAINS_FILE" 2>/dev/null; then
            echo -e "${YELLOW}! 域名已存在: $domain${NC}"
            ((duplicate_count++))
        else
            echo "$domain" >> "$DOMAINS_FILE"
            echo -e "${GREEN}✓ 添加成功: $domain${NC}"
            ((added_count++))
        fi
    done
    
    echo
    echo -e "${CYAN}统计: 添加 $added_count 个, 重复 $duplicate_count 个, 无效 $invalid_count 个${NC}"
    
    if [ $added_count -gt 0 ]; then
        systemctl restart $SERVICE_NAME
        echo -e "${GREEN}服务已重启，新域名将被监控${NC}"
    fi
}

delete_domain() {
    echo -e "${BLUE}删除监控域名${NC}"
    
    if [[ ! -f "$DOMAINS_FILE" ]] || [[ ! -s "$DOMAINS_FILE" ]]; then
        echo -e "${YELLOW}监控列表为空${NC}"
        return
    fi
    
    echo -e "${YELLOW}当前监控的域名:${NC}"
    cat -n "$DOMAINS_FILE"
    echo
    echo -e "${CYAN}输入域名编号删除单个，输入 'all' 清空所有域名${NC}"
    read -p "请输入选择: " choice
    
    if [[ "$choice" == "all" ]]; then
        read -p "确定要清空所有域名吗? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            > "$DOMAINS_FILE"
            echo -e "${GREEN}已清空所有域名${NC}"
            systemctl restart $SERVICE_NAME
        fi
    elif [[ "$choice" =~ ^[0-9]+$ ]]; then
        domain=$(sed -n "${choice}p" "$DOMAINS_FILE")
        if [[ -n "$domain" ]]; then
            sed -i "${choice}d" "$DOMAINS_FILE"
            echo -e "${GREEN}已删除域名: $domain${NC}"
            systemctl restart $SERVICE_NAME
        else
            echo -e "${RED}无效的编号${NC}"
        fi
    else
        echo -e "${RED}无效的输入${NC}"
    fi
}

configure_telegram() {
    echo -e "${BLUE}配置Telegram Bot通知${NC}"
    echo
    echo -e "${YELLOW}获取Bot Token和Chat ID的步骤:${NC}"
    echo "1. 在Telegram搜索 @BotFather"
    echo "2. 发送 /newbot 创建机器人"
    echo "3. 按提示设置机器人名称和用户名"
    echo "4. 复制Bot Token"
    echo "5. 搜索并打开您的机器人，发送任意消息"
    echo "6. 访问: https://api.telegram.org/bot<TOKEN>/getUpdates"
    echo "7. 找到 \"chat\":{\"id\":数字} 中的数字即为Chat ID"
    echo
    
    # 显示当前配置
    current_token=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c.get('telegram',{}).get('bot_token',''))" 2>/dev/null)
    current_chat=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c.get('telegram',{}).get('chat_id',''))" 2>/dev/null)
    
    if [[ -n "$current_token" ]]; then
        echo -e "${CYAN}当前Bot Token: ${current_token:0:10}...${current_token: -4}${NC}"
    fi
    if [[ -n "$current_chat" ]]; then
        echo -e "${CYAN}当前Chat ID: $current_chat${NC}"
    fi
    echo
    
    read -p "请输入Bot Token (回车保持当前): " bot_token
    read -p "请输入Chat ID (回车保持当前): " chat_id
    
    # 如果为空则保持当前值
    bot_token=${bot_token:-$current_token}
    chat_id=${chat_id:-$current_chat}
    
    if [[ -z "$bot_token" ]] || [[ -z "$chat_id" ]]; then
        echo -e "${RED}Bot Token和Chat ID不能为空${NC}"
        return
    fi
    
    # 验证Bot Token
    echo -e "\n${YELLOW}验证Bot Token...${NC}"
    response=$(curl -s "https://api.telegram.org/bot$bot_token/getMe")
    if echo "$response" | grep -q '"ok":true'; then
        bot_name=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['username'])" 2>/dev/null)
        echo -e "${GREEN}✓ Bot验证成功: @$bot_name${NC}"
    else
        echo -e "${RED}✗ Bot Token无效${NC}"
        return
    fi
    
    # 更新配置
    python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
except:
    config = {}
    
config['telegram'] = {'bot_token': '$bot_token', 'chat_id': '$chat_id'}
if 'check_interval' not in config:
    config['check_interval'] = 60
if 'notify_days_before_expiry' not in config:
    config['notify_days_before_expiry'] = [30, 7, 3, 1]
    
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
    
    echo -e "${GREEN}Telegram配置成功${NC}"
    
    # 测试通知
    read -p "是否发送测试通知? (y/n): " test
    if [[ "$test" == "y" ]]; then
        curl -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" \
             -d "chat_id=$chat_id" \
             -d "text=✅ 域名监控系统配置成功！" \
             -d "parse_mode=HTML" > /dev/null
        echo -e "${GREEN}测试通知已发送${NC}"
    fi
    
    systemctl restart $SERVICE_NAME
}

delete_telegram() {
    echo -e "${BLUE}删除Telegram Bot通知${NC}"
    read -p "确定要删除Telegram配置吗? (yes/no): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
config['telegram'] = {'bot_token': '', 'chat_id': ''}
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
        echo -e "${GREEN}Telegram配置已删除${NC}"
        systemctl restart $SERVICE_NAME
    fi
}

list_domains() {
    echo -e "${BLUE}监控域名列表${NC}"
    
    if [[ ! -f "$DOMAINS_FILE" ]] || [[ ! -s "$DOMAINS_FILE" ]]; then
        echo -e "${YELLOW}监控列表为空${NC}"
    else
        total=$(wc -l < "$DOMAINS_FILE")
        echo -e "${GREEN}共监控 $total 个域名:${NC}"
        echo -e "${BLUE}----------------------------${NC}"
        cat -n "$DOMAINS_FILE"
        echo -e "${BLUE}----------------------------${NC}"
        
        # 显示最近检查状态
        if [[ -f "$INSTALL_DIR/history.json" ]]; then
            echo -e "\n${CYAN}最近检查状态:${NC}"
            python3 << EOF
import json
from datetime import datetime

try:
    with open('$INSTALL_DIR/history.json', 'r') as f:
        history = json.load(f)
    
    for domain, info in history.items():
        status = info.get('status', 'unknown')
        last_check = info.get('last_check', '')
        days_until_expiry = info.get('days_until_expiry')
        
        # 状态图标
        if status == 'available':
            status_icon = '✅'
            status_text = '可注册'
        elif status == 'registered':
            status_icon = '❌'
            status_text = '已注册'
        elif status == 'expired':
            status_icon = '💀'
            status_text = '已过期'
        else:
            status_icon = '⚠️'
            status_text = '未知'
        
        # 时间格式化
        if last_check:
            try:
                check_time = datetime.fromisoformat(last_check)
                time_str = check_time.strftime('%Y-%m-%d %H:%M')
            except:
                time_str = last_check
        else:
            time_str = '从未检查'
        
        # 过期信息
        expiry_info = ''
        if days_until_expiry is not None:
            if days_until_expiry < 0:
                expiry_info = f' (已过期{abs(days_until_expiry)}天)'
            elif days_until_expiry == 0:
                expiry_info = ' (今天过期!)'
            elif days_until_expiry < 30:
                expiry_info = f' (剩余{days_until_expiry}天)'
            
        print(f"{status_icon} {domain} - {status_text}{expiry_info} - {time_str}")
except:
    print("暂无历史记录")
EOF
        fi
    fi
}

check_status() {
    echo -e "${BLUE}服务状态${NC}"
    systemctl status $SERVICE_NAME --no-pager
    
    echo -e "\n${CYAN}检查配置:${NC}"
    interval=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('check_interval', 60))" 2>/dev/null)
    echo "检查间隔: $interval 分钟"
    
    # 显示下次检查时间
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "\n${CYAN}最近日志:${NC}"
        tail -n 5 $INSTALL_DIR/logs/monitor.log 2>/dev/null || echo "暂无日志"
    fi
}

restart_service() {
    echo -e "${BLUE}重启监控服务${NC}"
    systemctl restart $SERVICE_NAME
    sleep 2
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}✓ 服务重启成功${NC}"
    else
        echo -e "${RED}✗ 服务重启失败${NC}"
        echo -e "${YELLOW}查看错误信息:${NC}"
        journalctl -u $SERVICE_NAME -n 10 --no-pager
    fi
}

view_logs() {
    echo -e "${BLUE}查看运行日志 (按Ctrl+C退出)${NC}"
    echo -e "${CYAN}显示最近50行日志...${NC}"
    echo
    tail -n 50 -f $INSTALL_DIR/logs/monitor.log
}

check_now() {
    echo -e "${BLUE}立即检查所有域名${NC}"
    echo -e "${YELLOW}正在触发立即检查...${NC}"
    
    # 重启服务触发检查
    systemctl restart $SERVICE_NAME
    
    echo -e "${GREEN}已触发检查，请查看日志了解结果${NC}"
    echo -e "${CYAN}查看实时日志...${NC}"
    
    # 等待服务启动
    sleep 3
    
    # 显示日志
    timeout 30 tail -f $INSTALL_DIR/logs/monitor.log | while read line; do
        echo "$line"
        if echo "$line" | grep -q "域名检查完成"; then
            break
        fi
    done
}

change_interval() {
    echo -e "${BLUE}修改检查间隔${NC}"
    
    current=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('check_interval', 60))" 2>/dev/null)
    echo -e "${CYAN}当前检查间隔: $current 分钟${NC}"
    echo
    echo "建议值:"
    echo "  5  - 紧急监控 (域名即将释放)"
    echo "  15 - 高频监控 (重要域名)"
    echo "  30 - 常规监控"
    echo "  60 - 标准监控 (默认)"
    echo "  120 - 低频监控 (一般关注)"
    echo "  360 - 每日检查 (长期关注)"
    echo
    
    read -p "请输入新的检查间隔（分钟）: " interval
    
    if [[ "$interval" =~ ^[0-9]+$ ]] && [ $interval -ge 1 ] && [ $interval -le 1440 ]; then
        python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
config['check_interval'] = $interval
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
        echo -e "${GREEN}检查间隔已更新为 $interval 分钟${NC}"
        systemctl restart $SERVICE_NAME
    else
        echo -e "${RED}无效的间隔时间（1-1440分钟）${NC}"
    fi
}

view_history() {
    echo -e "${BLUE}查看检查历史${NC}"
    
    if [[ ! -f "$INSTALL_DIR/history.json" ]]; then
        echo -e "${YELLOW}暂无历史记录${NC}"
        return
    fi
    
    python3 << EOF
import json
from datetime import datetime

try:
    with open('$INSTALL_DIR/history.json', 'r') as f:
        history = json.load(f)
    
    if not history:
        print("暂无历史记录")
    else:
        print(f"共有 {len(history)} 个域名的历史记录\\n")
        
        # 分类统计
        available_count = sum(1 for d in history.values() if d.get('status') == 'available')
        registered_count = sum(1 for d in history.values() if d.get('status') == 'registered')
        expired_count = sum(1 for d in history.values() if d.get('status') == 'expired')
        
        print(f"统计信息:")
        print(f"  可注册: {available_count} 个")
        print(f"  已注册: {registered_count} 个")
        print(f"  已过期: {expired_count} 个")
        print()
        
        for domain, info in sorted(history.items()):
            print(f"域名: {domain}")
            
            status = info.get('status', 'unknown')
            status_emoji = {
                'available': '✅',
                'registered': '❌',
                'expired': '💀',
                'error': '⚠️'
            }.get(status, '❓')
            
            print(f"  状态: {status_emoji} {status}")
            
            last_check = info.get('last_check', '')
            if last_check:
                try:
                    check_time = datetime.fromisoformat(last_check)
                    print(f"  最后检查: {check_time.strftime('%Y-%m-%d %H:%M:%S')}")
                    # 计算距离现在的时间
                    time_diff = datetime.now() - check_time
                    if time_diff.days > 0:
                        print(f"  距今: {time_diff.days} 天前")
                    else:
                        hours = time_diff.seconds // 3600
                        minutes = (time_diff.seconds % 3600) // 60
                        print(f"  距今: {hours} 小时 {minutes} 分钟前")
                except:
                    print(f"  最后检查: {last_check}")
                    
            if info.get('expiry_date'):
                print(f"  过期时间: {info.get('expiry_date')}")
                
            if info.get('days_until_expiry') is not None:
                days = info.get('days_until_expiry')
                if days < 0:
                    print(f"  状态: 已过期 {abs(days)} 天")
                elif days == 0:
                    print(f"  状态: 今天过期!")
                else:
                    print(f"  剩余天数: {days} 天")
                
            if info.get('last_notified'):
                print(f"  最后通知: {info.get('last_notified')}")
                
            print()
except Exception as e:
    print(f"读取历史记录失败: {e}")
EOF
}

advanced_settings() {
    echo -e "${BLUE}高级设置${NC}"
    echo -e "${GREEN}1.${NC} 设置过期提醒天数"
    echo -e "${GREEN}2.${NC} 清理历史记录"
    echo -e "${GREEN}3.${NC} 导出域名列表"
    echo -e "${GREEN}4.${NC} 导入域名列表"
    echo -e "${GREEN}5.${NC} 查看系统信息"
    echo -e "${GREEN}0.${NC} 返回主菜单"
    echo
    read -p "请选择操作: " choice
    
    case $choice in
        1)
            echo -e "${CYAN}设置域名过期前多少天发送提醒${NC}"
            current_days=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('notify_days_before_expiry', [30,7,3,1]))" 2>/dev/null)
            echo "当前设置: $current_days"
            echo "请输入提醒天数（用空格分隔，如: 30 7 3 1）:"
            read -a days_array
            if [ ${#days_array[@]} -gt 0 ]; then
                python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
config['notify_days_before_expiry'] = [${days_array[@]}]
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
                echo -e "${GREEN}提醒天数已更新${NC}"
                systemctl restart $SERVICE_NAME
            fi
            ;;
        2)
            echo -e "${YELLOW}清理历史记录${NC}"
            read -p "确定要清理所有历史记录吗? (yes/no): " confirm
            if [[ "$confirm" == "yes" ]]; then
                echo '{}' > $INSTALL_DIR/history.json
                echo -e "${GREEN}历史记录已清理${NC}"
            fi
            ;;
        3)
            echo -e "${CYAN}导出域名列表${NC}"
            if [[ -f "$DOMAINS_FILE" ]] && [[ -s "$DOMAINS_FILE" ]]; then
                export_file="/tmp/domainmonitor_domains_$(date +%Y%m%d_%H%M%S).txt"
                cp "$DOMAINS_FILE" "$export_file"
                echo -e "${GREEN}域名列表已导出到: $export_file${NC}"
                echo -e "${CYAN}文件内容:${NC}"
                cat "$export_file"
            else
                echo -e "${YELLOW}域名列表为空${NC}"
            fi
            ;;
        4)
            echo -e "${CYAN}导入域名列表${NC}"
            read -p "请输入要导入的文件路径: " import_file
            if [[ -f "$import_file" ]]; then
                imported=0
                skipped=0
                while IFS= read -r domain; do
                    domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
                    if [[ -n "$domain" ]] && validate_domain "$domain"; then
                        if ! grep -q "^$domain$" "$DOMAINS_FILE" 2>/dev/null; then
                            echo "$domain" >> "$DOMAINS_FILE"
                            echo -e "${GREEN}✓ 导入: $domain${NC}"
                            ((imported++))
                        else
                            ((skipped++))
                        fi
                    fi
                done < "$import_file"
                echo -e "${GREEN}导入完成: 成功 $imported 个, 跳过 $skipped 个${NC}"
                if [ $imported -gt 0 ]; then
                    systemctl restart $SERVICE_NAME
                fi
            else
                echo -e "${RED}文件不存在${NC}"
            fi
            ;;
        5)
            echo -e "${CYAN}系统信息${NC}"
            echo "========================"
            echo "安装目录: $INSTALL_DIR"
            echo "配置文件: $CONFIG_FILE"
            echo "域名列表: $DOMAINS_FILE"
            echo "历史记录: $INSTALL_DIR/history.json"
            echo "日志文件: $INSTALL_DIR/logs/monitor.log"
            echo "服务名称: $SERVICE_NAME"
            echo "========================"
            echo
            echo "Python版本:"
            python3 --version
            echo
            echo "已安装的Python包:"
            pip3 list 2>/dev/null | grep -E "requests|schedule|python-telegram-bot" || echo "无法获取包信息"
            echo
            echo "磁盘使用情况:"
            du -sh $INSTALL_DIR 2>/dev/null
            echo
            echo "日志文件大小:"
            ls -lh $INSTALL_DIR/logs/monitor.log 2>/dev/null || echo "暂无日志"
            ;;
    esac
}

uninstall() {
    echo -e "${RED}警告: 此操作将删除所有配置和数据！${NC}"
    echo -e "${YELLOW}将删除:${NC}"
    echo "  - 监控服务"
    echo "  - 所有配置文件"
    echo "  - 监控域名列表"
    echo "  - 历史记录"
    echo "  - 日志文件"
    echo
    read -p "确定要卸载吗? (yes/no): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        echo -e "${YELLOW}正在卸载...${NC}"
        
        # 停止和删除服务
        systemctl stop $SERVICE_NAME 2>/dev/null
        systemctl disable $SERVICE_NAME 2>/dev/null
        rm -f /etc/systemd/system/$SERVICE_NAME.service
        systemctl daemon-reload
        
        # 备份数据
        if [[ -d "$INSTALL_DIR" ]]; then
            backup_file="/tmp/domainmonitor_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
            tar -czf "$backup_file" -C /opt domainmonitor 2>/dev/null
            echo -e "${CYAN}数据已备份到: $backup_file${NC}"
        fi
        
        # 删除目录
        rm -rf $INSTALL_DIR
        
        echo -e "${GREEN}域名监控系统已卸载${NC}"
        echo -e "${YELLOW}感谢使用！${NC}"
        echo
        echo -e "${CYAN}如需重新安装，请运行:${NC}"
        echo "bash <(curl -sSL https://raw.githubusercontent.com/everett7623/domainmonitor/main/install.sh)"
        exit 0
    else
        echo -e "${YELLOW}取消卸载${NC}"
    fi
}

# 显示快捷帮助
show_help() {
    echo -e "${CYAN}快捷操作提示:${NC}"
    echo "• 添加域名后会自动重启服务并开始监控"
    echo "• 建议先配置Telegram通知再添加域名"
    echo "• 可以通过修改检查间隔来调整监控频率"
    echo "• 使用'立即检查'功能可以手动触发一次检查"
    echo "• 历史记录会保存所有检查结果"
    echo
}

# 主循环
while true; do
    show_menu
    read -p "请选择操作 [0-13]: " choice
    
    case $choice in
        1) add_domain ;;
        2) delete_domain ;;
        3) configure_telegram ;;
        4) delete_telegram ;;
        5) list_domains ;;
        6) check_status ;;
        7) restart_service ;;
        8) view_logs ;;
        9) check_now ;;
        10) change_interval ;;
        11) view_history ;;
        12) advanced_settings ;;
        13) uninstall ;;
        0) 
            echo -e "${GREEN}感谢使用域名监控系统！${NC}"
            echo -e "${CYAN}GitHub: https://github.com/everett7623/domainmonitor${NC}"
            exit 0 
            ;;
        h|H|help|HELP) show_help ;;
        *) echo -e "${RED}无效的选择，请输入 0-13 的数字${NC}" ;;
    esac
    
    echo
    read -p "按Enter键继续..."
done
