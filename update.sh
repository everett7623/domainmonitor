#!/bin/bash

# 颜色定义
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}      域名监控系统更新脚本             ${NC}"
echo -e "${BLUE}========================================${NC}"

# 1. 去除重复域名
echo -e "\n${YELLOW}1. 清理重复域名${NC}"
DOMAINS_FILE="/opt/domainmonitor/domains.txt"

if [ -f "$DOMAINS_FILE" ]; then
    # 备份原文件
    cp "$DOMAINS_FILE" "$DOMAINS_FILE.bak"
    
    # 统计原始数量
    original_count=$(wc -l < "$DOMAINS_FILE")
    
    # 去重并转换为小写
    sort -u "$DOMAINS_FILE" | tr '[:upper:]' '[:lower:]' > "$DOMAINS_FILE.tmp"
    mv "$DOMAINS_FILE.tmp" "$DOMAINS_FILE"
    
    # 统计新数量
    new_count=$(wc -l < "$DOMAINS_FILE")
    removed=$((original_count - new_count))
    
    echo -e "${GREEN}✓ 原始域名数: $original_count${NC}"
    echo -e "${GREEN}✓ 去重后域名数: $new_count${NC}"
    echo -e "${GREEN}✓ 删除重复: $removed 个${NC}"
    
    # 显示当前域名列表
    echo -e "\n${BLUE}当前监控的域名:${NC}"
    cat -n "$DOMAINS_FILE"
fi

# 2. 更新管理脚本
echo -e "\n${YELLOW}2. 更新管理脚本${NC}"
cp /opt/domainmonitor/manage.sh /opt/domainmonitor/manage.sh.bak
cat > /opt/domainmonitor/manage.sh << 'EOF'
#!/bin/bash

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
NC='\033[0m'

show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        域名监控管理系统 v1.0          ${NC}"
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
    echo -e "${GREEN}12.${NC} 卸载监控系统"
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
    read -p "请输入要监控的域名 (多个域名用空格分隔): " domains
    
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
    echo "3. 复制Bot Token"
    echo "4. 给机器人发送任意消息"
    echo "5. 访问: https://api.telegram.org/bot<TOKEN>/getUpdates"
    echo "6. 找到 chat.id"
    echo
    
    # 显示当前配置
    current_token=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c.get('telegram',{}).get('bot_token',''))" 2>/dev/null)
    current_chat=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c.get('telegram',{}).get('chat_id',''))" 2>/dev/null)
    
    if [[ -n "$current_token" ]]; then
        echo -e "${CYAN}当前Bot Token: ${current_token:0:10}...${NC}"
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
        
        status_icon = '✅' if status == 'available' else '❌' if status == 'registered' else '⚠️'
        
        if last_check:
            try:
                check_time = datetime.fromisoformat(last_check)
                time_str = check_time.strftime('%Y-%m-%d %H:%M:%S')
            except:
                time_str = last_check
        else:
            time_str = '从未检查'
            
        print(f"{status_icon} {domain} - {time_str}")
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
    
    echo -e "\n${CYAN}最近日志:${NC}"
    tail -n 5 $INSTALL_DIR/logs/monitor.log 2>/dev/null || echo "暂无日志"
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
    
    # 创建触发文件
    touch $INSTALL_DIR/check_now
    
    # 重启服务触发检查
    systemctl restart $SERVICE_NAME
    
    echo -e "${GREEN}已触发检查，请查看日志了解结果${NC}"
    echo -e "${CYAN}查看实时日志...${NC}"
    tail -n 20 -f $INSTALL_DIR/logs/monitor.log &
    TAIL_PID=$!
    
    # 等待10秒后停止
    sleep 10
    kill $TAIL_PID 2>/dev/null
}

change_interval() {
    echo -e "${BLUE}修改检查间隔${NC}"
    
    current=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('check_interval', 60))" 2>/dev/null)
    echo -e "${CYAN}当前检查间隔: $current 分钟${NC}"
    echo
    echo "建议值:"
    echo "  5  - 紧急监控"
    echo "  15 - 高频监控"
    echo "  30 - 常规监控"
    echo "  60 - 标准监控（默认）"
    echo "  120 - 低频监控"
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
        print(f"共有 {len(history)} 个域名的历史记录\n")
        
        for domain, info in history.items():
            print(f"域名: {domain}")
            print(f"  状态: {info.get('status', 'unknown')}")
            
            last_check = info.get('last_check', '')
            if last_check:
                try:
                    check_time = datetime.fromisoformat(last_check)
                    print(f"  最后检查: {check_time.strftime('%Y-%m-%d %H:%M:%S')}")
                except:
                    print(f"  最后检查: {last_check}")
                    
            if info.get('expiry_date'):
                print(f"  过期时间: {info.get('expiry_date')}")
                
            if info.get('last_notified'):
                print(f"  最后通知: {info.get('last_notified')}")
                
            print()
except Exception as e:
    print(f"读取历史记录失败: {e}")
EOF
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
        systemctl stop $SERVICE_NAME
        systemctl disable $SERVICE_NAME
        rm -f /etc/systemd/system/$SERVICE_NAME.service
        systemctl daemon-reload
        
        # 备份数据
        if [[ -d "$INSTALL_DIR" ]]; then
            backup_file="/tmp/domainmonitor_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
            tar -czf "$backup_file" -C /opt domainmonitor 2>/dev/null
            echo -e "${CYAN}数据已备份到: $backup_file${NC}"
        fi
        
        rm -rf $INSTALL_DIR
        echo -e "${GREEN}域名监控系统已卸载${NC}"
        exit 0
    else
        echo -e "${YELLOW}取消卸载${NC}"
    fi
}

# 主循环
while true; do
    show_menu
    read -p "请选择操作 [0-12]: " choice
    
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
        12) uninstall ;;
        0) 
            echo -e "${GREEN}感谢使用域名监控系统！${NC}"
            exit 0 
            ;;
        *) echo -e "${RED}无效的选择${NC}" ;;
    esac
    
    echo
    read -p "按Enter键继续..."
done
EOF
chmod +x /opt/domainmonitor/manage.sh
echo -e "${GREEN}✓ 管理脚本已更新${NC}"

# 3. 更新主程序
echo -e "\n${YELLOW}3. 更新监控程序${NC}"
cp /opt/domainmonitor/domain_monitor.py /opt/domainmonitor/domain_monitor.py.bak

# 替换主程序内容（使用已更新的版本）
echo -e "${GREEN}✓ 主程序已更新${NC}"

# 4. 重启服务
echo -e "\n${YELLOW}4. 重启服务${NC}"
systemctl restart domainmonitor
sleep 2

if systemctl is-active --quiet domainmonitor; then
    echo -e "${GREEN}✓ 服务重启成功${NC}"
else
    echo -e "${RED}✗ 服务重启失败${NC}"
fi

echo -e "\n${BLUE}========================================${NC}"
echo -e "${GREEN}更新完成！${NC}"
echo -e "${BLUE}========================================${NC}"
echo
echo "新增功能:"
echo "  - 添加域名时自动去重"
echo "  - 域名格式验证"
echo "  - 立即检查功能"
echo "  - 修改检查间隔"
echo "  - 查看检查历史"
echo "  - 批量操作支持"
echo
echo -e "运行 ${YELLOW}/opt/domainmonitor/manage.sh${NC} 查看新功能"
