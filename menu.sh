#!/bin/bash

# 域名监控服务 - 交互式管理菜单
# 提供友好的菜单界面管理所有功能

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color
BOLD='\033[1m'

# 配置
PROJECT_DIR="/opt/domain-monitor"
CONFIG_FILE="$PROJECT_DIR/config.env"
DOMAINS_FILE="$PROJECT_DIR/domains.json"
LOG_FILE="/var/log/domain-monitor.log"

# 检查是否在正确的目录
check_directory() {
    if [ ! -d "$PROJECT_DIR" ]; then
        echo -e "${RED}错误：项目目录不存在！${NC}"
        echo "请先运行部署脚本：./deploy.sh"
        exit 1
    fi
    cd "$PROJECT_DIR"
}

# 显示标题
show_header() {
    clear
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BOLD}${BLUE}                         域名监控服务管理系统 v1.0                          ${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

# 显示服务状态
show_status() {
    echo -e "${YELLOW}服务状态：${NC}"
    if sudo supervisorctl status domain-monitor 2>/dev/null | grep -q "RUNNING"; then
        echo -e "${GREEN}● 域名监控服务正在运行${NC}"
        local uptime=$(sudo supervisorctl status domain-monitor | awk '{print $5, $6}')
        echo -e "  运行时间：$uptime"
    else
        echo -e "${RED}● 域名监控服务已停止${NC}"
    fi
    
    # 显示配置状态
    if [ -f "$CONFIG_FILE" ]; then
        echo -e "${GREEN}● 配置文件已设置${NC}"
    else
        echo -e "${RED}● 配置文件未设置${NC}"
    fi
    
    # 显示监控域名数量
    if [ -f "$DOMAINS_FILE" ]; then
        local domain_count=$(python3 -c "import json; print(len(json.load(open('$DOMAINS_FILE'))))" 2>/dev/null || echo "0")
        echo -e "${BLUE}● 监控域名数量：${domain_count}${NC}"
    fi
    echo ""
}

# 主菜单
show_main_menu() {
    echo -e "${BOLD}主菜单：${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "  ${BOLD}1)${NC} 🚀 快速开始（配置向导）"
    echo -e "  ${BOLD}2)${NC} 📋 域名管理"
    echo -e "  ${BOLD}3)${NC} ⚙️  服务控制"
    echo -e "  ${BOLD}4)${NC} 📊 查看日志"
    echo -e "  ${BOLD}5)${NC} 🔧 系统设置"
    echo -e "  ${BOLD}6)${NC} 📈 统计信息"
    echo -e "  ${BOLD}0)${NC} 退出"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 快速开始向导
quick_start() {
    show_header
    echo -e "${BOLD}${GREEN}快速开始向导${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    # 检查配置
    if [ ! -f "$CONFIG_FILE" ]; then
        echo -e "${YELLOW}首次使用，需要配置 Telegram Bot${NC}"
        echo ""
        configure_telegram
    else
        echo -e "${GREEN}✓ Telegram 已配置${NC}"
    fi
    
    # 添加域名
    echo ""
    echo -e "${YELLOW}添加要监控的域名：${NC}"
    read -p "请输入域名（如 example.com）: " domain
    if [ ! -z "$domain" ]; then
        read -p "添加备注（可选）: " notes
        ./manage.sh add "$domain" "$notes"
        echo -e "${GREEN}✓ 域名已添加${NC}"
    fi
    
    # 启动服务
    echo ""
    read -p "是否立即启动监控服务？(y/n): " start_now
    if [[ "$start_now" =~ ^[Yy]$ ]]; then
        sudo supervisorctl start domain-monitor 2>/dev/null
        echo -e "${GREEN}✓ 服务已启动${NC}"
    fi
    
    echo ""
    read -p "按回车键返回主菜单..."
}

# 配置 Telegram
configure_telegram() {
    echo -e "${BOLD}配置 Telegram Bot${NC}"
    echo ""
    echo -e "${CYAN}获取 Bot Token 的步骤：${NC}"
    echo "1. 在 Telegram 中搜索 @BotFather"
    echo "2. 发送 /newbot 创建新机器人"
    echo "3. 复制生成的 Token"
    echo ""
    
    read -p "请输入 Bot Token: " bot_token
    while [ -z "$bot_token" ]; do
        echo -e "${RED}Token 不能为空！${NC}"
        read -p "请输入 Bot Token: " bot_token
    done
    
    echo ""
    echo -e "${CYAN}获取 Chat ID 的步骤：${NC}"
    echo "1. 给你的 Bot 发送任意消息"
    echo "2. 访问: https://api.telegram.org/bot${bot_token}/getUpdates"
    echo "3. 找到 chat.id 的值"
    echo ""
    
    read -p "请输入 Chat ID: " chat_id
    while [ -z "$chat_id" ]; do
        echo -e "${RED}Chat ID 不能为空！${NC}"
        read -p "请输入 Chat ID: " chat_id
    done
    
    read -p "检查间隔（分钟，默认60）: " interval
    if [ -z "$interval" ]; then
        interval=60
    fi
    
    # 保存配置
    cat > "$CONFIG_FILE" << EOF
TELEGRAM_BOT_TOKEN=$bot_token
TELEGRAM_CHAT_ID=$chat_id
CHECK_INTERVAL_MINUTES=$interval
EOF
    chmod 600 "$CONFIG_FILE"
    
    echo -e "${GREEN}✓ 配置已保存${NC}"
}

# 域名管理菜单
domain_management() {
    while true; do
        show_header
        echo -e "${BOLD}${BLUE}域名管理${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # 显示当前域名列表
        echo -e "${YELLOW}当前监控的域名：${NC}"
        if [ -f "$DOMAINS_FILE" ] && [ -s "$DOMAINS_FILE" ]; then
            python3 -c "
import json
from datetime import datetime

with open('$DOMAINS_FILE', 'r') as f:
    domains = json.load(f)

if not domains:
    print('  (暂无域名)')
else:
    print(f'{'域名':<30} {'状态':<15} {'最后检查':<20} {'备注':<30}')
    print('-' * 95)
    for domain, info in domains.items():
        status = info.get('status', '未知')
        if status == 'available':
            status = '\033[32m可注册\033[0m'
        elif status == 'registered':
            status = '\033[31m已注册\033[0m'
        
        last_check = info.get('last_checked', '从未检查')
        if last_check != '从未检查':
            try:
                dt = datetime.fromisoformat(last_check.replace('Z', '+00:00'))
                last_check = dt.strftime('%Y-%m-%d %H:%M')
            except:
                pass
        
        notes = info.get('notes', '')[:30]
        print(f'{domain:<30} {status:<24} {last_check:<20} {notes:<30}')
"
        else
            echo "  (暂无域名)"
        fi
        
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${BOLD}1)${NC} ➕ 添加域名"
        echo -e "  ${BOLD}2)${NC} ➖ 删除域名"
        echo -e "  ${BOLD}3)${NC} 📝 批量添加域名"
        echo -e "  ${BOLD}4)${NC} 🔍 立即检查所有域名"
        echo -e "  ${BOLD}5)${NC} 📤 导出域名列表"
        echo -e "  ${BOLD}0)${NC} 返回主菜单"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        read -p "请选择操作 [0-5]: " choice
        
        case $choice in
            1)
                echo ""
                read -p "请输入要添加的域名: " domain
                if [ ! -z "$domain" ]; then
                    read -p "添加备注（可选）: " notes
                    ./manage.sh add "$domain" "$notes"
                    echo -e "${GREEN}✓ 域名已添加${NC}"
                    sleep 2
                fi
                ;;
            2)
                echo ""
                read -p "请输入要删除的域名: " domain
                if [ ! -z "$domain" ]; then
                    ./manage.sh remove "$domain"
                    echo -e "${GREEN}✓ 域名已删除${NC}"
                    sleep 2
                fi
                ;;
            3)
                echo ""
                echo "批量添加域名（每行一个域名，输入空行结束）："
                while true; do
                    read -p "> " domain
                    if [ -z "$domain" ]; then
                        break
                    fi
                    ./manage.sh add "$domain" "批量添加"
                done
                echo -e "${GREEN}✓ 批量添加完成${NC}"
                sleep 2
                ;;
            4)
                echo ""
                echo -e "${YELLOW}正在检查所有域名...${NC}"
                ./manage.sh check
                echo -e "${GREEN}✓ 检查完成${NC}"
                read -p "按回车键继续..."
                ;;
            5)
                echo ""
                timestamp=$(date +%Y%m%d_%H%M%S)
                export_file="domains_export_${timestamp}.txt"
                python3 -c "
import json
with open('$DOMAINS_FILE', 'r') as f:
    domains = json.load(f)
with open('$export_file', 'w') as f:
    for domain in domains:
        f.write(domain + '\n')
"
                echo -e "${GREEN}✓ 域名列表已导出到：$export_file${NC}"
                read -p "按回车键继续..."
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# 服务控制菜单
service_control() {
    while true; do
        show_header
        echo -e "${BOLD}${BLUE}服务控制${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # 显示当前状态
        show_status
        
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${BOLD}1)${NC} ▶️  启动服务"
        echo -e "  ${BOLD}2)${NC} ⏸️  停止服务"
        echo -e "  ${BOLD}3)${NC} 🔄 重启服务"
        echo -e "  ${BOLD}4)${NC} 📊 查看详细状态"
        echo -e "  ${BOLD}0)${NC} 返回主菜单"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        read -p "请选择操作 [0-4]: " choice
        
        case $choice in
            1)
                echo ""
                sudo supervisorctl start domain-monitor
                echo -e "${GREEN}✓ 服务启动命令已执行${NC}"
                sleep 2
                ;;
            2)
                echo ""
                sudo supervisorctl stop domain-monitor
                echo -e "${YELLOW}✓ 服务停止命令已执行${NC}"
                sleep 2
                ;;
            3)
                echo ""
                sudo supervisorctl restart domain-monitor
                echo -e "${GREEN}✓ 服务重启命令已执行${NC}"
                sleep 2
                ;;
            4)
                echo ""
                sudo supervisorctl status domain-monitor
                echo ""
                read -p "按回车键继续..."
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# 查看日志
view_logs() {
    while true; do
        show_header
        echo -e "${BOLD}${BLUE}日志查看${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${BOLD}1)${NC} 📜 查看最新日志（最后50行）"
        echo -e "  ${BOLD}2)${NC} 🔄 实时查看日志"
        echo -e "  ${BOLD}3)${NC} 🔍 搜索日志"
        echo -e "  ${BOLD}4)${NC} 📊 查看错误日志"
        echo -e "  ${BOLD}5)${NC} 🗑️  清空日志"
        echo -e "  ${BOLD}0)${NC} 返回主菜单"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        read -p "请选择操作 [0-5]: " choice
        
        case $choice in
            1)
                echo ""
                echo -e "${YELLOW}最新日志（最后50行）：${NC}"
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                sudo tail -n 50 "$LOG_FILE"
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                read -p "按回车键继续..."
                ;;
            2)
                echo ""
                echo -e "${YELLOW}实时日志查看（按 Ctrl+C 退出）：${NC}"
                sudo tail -f "$LOG_FILE"
                ;;
            3)
                echo ""
                read -p "请输入要搜索的关键词: " keyword
                if [ ! -z "$keyword" ]; then
                    echo -e "${YELLOW}搜索结果：${NC}"
                    sudo grep -i "$keyword" "$LOG_FILE" | tail -n 20
                    read -p "按回车键继续..."
                fi
                ;;
            4)
                echo ""
                echo -e "${YELLOW}错误日志：${NC}"
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                sudo grep -E "(ERROR|error|Error)" "$LOG_FILE" | tail -n 30
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                read -p "按回车键继续..."
                ;;
            5)
                echo ""
                read -p "确定要清空日志吗？(y/n): " confirm
                if [[ "$confirm" =~ ^[Yy]$ ]]; then
                    sudo truncate -s 0 "$LOG_FILE"
                    echo -e "${GREEN}✓ 日志已清空${NC}"
                fi
                sleep 2
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# 系统设置
system_settings() {
    while true; do
        show_header
        echo -e "${BOLD}${BLUE}系统设置${NC}"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        # 显示当前配置
        if [ -f "$CONFIG_FILE" ]; then
            echo -e "${YELLOW}当前配置：${NC}"
            source "$CONFIG_FILE"
            echo "  Bot Token: ${TELEGRAM_BOT_TOKEN:0:20}..."
            echo "  Chat ID: $TELEGRAM_CHAT_ID"
            echo "  检查间隔: $CHECK_INTERVAL_MINUTES 分钟"
        else
            echo -e "${RED}配置文件不存在${NC}"
        fi
        
        echo ""
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo -e "  ${BOLD}1)${NC} 🔧 修改 Telegram 配置"
        echo -e "  ${BOLD}2)${NC} ⏱️  修改检查间隔"
        echo -e "  ${BOLD}3)${NC} 🔐 查看完整配置"
        echo -e "  ${BOLD}4)${NC} 💾 备份配置"
        echo -e "  ${BOLD}5)${NC} 📥 恢复配置"
        echo -e "  ${BOLD}0)${NC} 返回主菜单"
        echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        
        read -p "请选择操作 [0-5]: " choice
        
        case $choice in
            1)
                echo ""
                configure_telegram
                echo -e "${YELLOW}需要重启服务才能生效${NC}"
                read -p "是否立即重启服务？(y/n): " restart
                if [[ "$restart" =~ ^[Yy]$ ]]; then
                    sudo supervisorctl restart domain-monitor
                fi
                ;;
            2)
                echo ""
                source "$CONFIG_FILE"
                echo "当前检查间隔：$CHECK_INTERVAL_MINUTES 分钟"
                read -p "请输入新的检查间隔（分钟）: " new_interval
                if [ ! -z "$new_interval" ]; then
                    sed -i "s/CHECK_INTERVAL_MINUTES=.*/CHECK_INTERVAL_MINUTES=$new_interval/" "$CONFIG_FILE"
                    echo -e "${GREEN}✓ 检查间隔已更新${NC}"
                    echo -e "${YELLOW}需要重启服务才能生效${NC}"
                fi
                sleep 2
                ;;
            3)
                echo ""
                echo -e "${YELLOW}完整配置内容：${NC}"
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                cat "$CONFIG_FILE"
                echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
                read -p "按回车键继续..."
                ;;
            4)
                echo ""
                timestamp=$(date +%Y%m%d_%H%M%S)
                backup_dir="backup_${timestamp}"
                mkdir -p "$backup_dir"
                cp "$CONFIG_FILE" "$backup_dir/"
                cp "$DOMAINS_FILE" "$backup_dir/"
                echo -e "${GREEN}✓ 配置已备份到：$backup_dir${NC}"
                read -p "按回车键继续..."
                ;;
            5)
                echo ""
                echo "可用的备份："
                ls -d backup_* 2>/dev/null || echo "  (没有备份)"
                read -p "请输入要恢复的备份目录名: " backup_dir
                if [ -d "$backup_dir" ]; then
                    cp "$backup_dir"/* .
                    echo -e "${GREEN}✓ 配置已恢复${NC}"
                else
                    echo -e "${RED}备份目录不存在${NC}"
                fi
                sleep 2
                ;;
            0)
                return
                ;;
            *)
                echo -e "${RED}无效选择${NC}"
                sleep 1
                ;;
        esac
    done
}

# 统计信息
show_statistics() {
    show_header
    echo -e "${BOLD}${BLUE}统计信息${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if [ -f "$DOMAINS_FILE" ]; then
        python3 -c "
import json
from datetime import datetime

with open('$DOMAINS_FILE', 'r') as f:
    domains = json.load(f)

total = len(domains)
available = sum(1 for d in domains.values() if d.get('status') == 'available')
registered = sum(1 for d in domains.values() if d.get('status') == 'registered')
unknown = total - available - registered

print(f'总监控域名数: {total}')
print(f'可注册域名数: {available}')
print(f'已注册域名数: {registered}')
print(f'未知状态域名: {unknown}')
print('')

# 最近检查的域名
recent = []
for domain, info in domains.items():
    if info.get('last_checked'):
        try:
            dt = datetime.fromisoformat(info['last_checked'].replace('Z', '+00:00'))
            recent.append((domain, dt))
        except:
            pass

if recent:
    recent.sort(key=lambda x: x[1], reverse=True)
    print('最近检查的域名:')
    for domain, dt in recent[:5]:
        print(f'  {domain} - {dt.strftime(\"%Y-%m-%d %H:%M\")}')
"
    else
        echo "暂无统计数据"
    fi
    
    echo ""
    # 日志统计
    if [ -f "$LOG_FILE" ]; then
        echo -e "${YELLOW}日志统计：${NC}"
        echo "  日志文件大小: $(du -h "$LOG_FILE" | cut -f1)"
        echo "  总行数: $(wc -l < "$LOG_FILE")"
        echo "  错误数: $(grep -c ERROR "$LOG_FILE" 2>/dev/null || echo 0)"
    fi
    
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    read -p "按回车键返回主菜单..."
}

# 主循环
main() {
    check_directory
    
    while true; do
        show_header
        show_status
        show_main_menu
        
        read -p "请选择操作 [0-6]: " choice
        
        case $choice in
            1) quick_start ;;
            2) domain_management ;;
            3) service_control ;;
            4) view_logs ;;
            5) system_settings ;;
            6) show_statistics ;;
            0)
                echo ""
                echo -e "${GREEN}感谢使用域名监控服务！${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}无效选择，请重新输入${NC}"
                sleep 1
                ;;
        esac
    done
}

# 运行主程序
main
