#!/bin/bash
# ====================================
# Domain Monitor 管理工具
# 作者: everett7623
# 描述: 用于管理域名监控服务的命令行工具
# ====================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m'

# 配置变量
INSTALL_DIR="/opt/domainmonitor"
CONFIG_FILE="${INSTALL_DIR}/config.json"
SERVICE_NAME="domainmonitor"
LOG_FILE="${INSTALL_DIR}/logs/monitor.log"

# 检测 Python 可执行文件
if [[ -f ${INSTALL_DIR}/venv/bin/python ]]; then
    PYTHON_CMD="${INSTALL_DIR}/venv/bin/python"
else
    PYTHON_CMD="python3"
fi

# 检查权限
check_permission() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[错误]${NC} 此命令需要 root 权限"
        echo -e "${YELLOW}请使用: sudo domainctl $@${NC}"
        exit 1
    fi
}

# 打印信息函数
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

# 显示帮助信息
show_help() {
    echo -e "${PURPLE}Domain Monitor 管理工具${NC}"
    echo
    echo -e "${CYAN}用法:${NC}"
    echo -e "  domainctl <command> [options]"
    echo
    echo -e "${CYAN}命令:${NC}"
    echo -e "  ${GREEN}start${NC}              启动监控服务"
    echo -e "  ${GREEN}stop${NC}               停止监控服务"
    echo -e "  ${GREEN}restart${NC}            重启监控服务"
    echo -e "  ${GREEN}status${NC}             查看服务状态"
    echo -e "  ${GREEN}logs${NC}               查看实时日志"
    echo -e "  ${GREEN}add <domain>${NC}       添加要监控的域名"
    echo -e "  ${GREEN}remove <domain>${NC}    删除监控的域名"
    echo -e "  ${GREEN}list${NC}               列出所有监控的域名"
    echo -e "  ${GREEN}check <domain>${NC}     立即检查指定域名"
    echo -e "  ${GREEN}report${NC}             生成监控报告"
    echo -e "  ${GREEN}config${NC}             查看配置信息"
    echo -e "  ${GREEN}update${NC}             更新程序"
    echo -e "  ${GREEN}uninstall${NC}          卸载程序"
    echo -e "  ${GREEN}help${NC}               显示此帮助信息"
    echo
    echo -e "${CYAN}示例:${NC}"
    echo -e "  domainctl add example.com      # 添加域名"
    echo -e "  domainctl remove example.com   # 删除域名"
    echo -e "  domainctl logs                 # 查看日志"
    echo -e "  domainctl status               # 查看状态"
    echo
}

# 启动服务
start_service() {
    check_permission
    print_info "启动 Domain Monitor 服务..."
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        print_warning "服务已经在运行中"
    else
        systemctl start ${SERVICE_NAME}
        sleep 2
        if systemctl is-active --quiet ${SERVICE_NAME}; then
            print_success "服务启动成功"
        else
            print_error "服务启动失败"
            echo -e "${YELLOW}查看错误日志: journalctl -u ${SERVICE_NAME} -n 50${NC}"
            exit 1
        fi
    fi
}

# 停止服务
stop_service() {
    check_permission
    print_info "停止 Domain Monitor 服务..."
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        systemctl stop ${SERVICE_NAME}
        sleep 2
        if ! systemctl is-active --quiet ${SERVICE_NAME}; then
            print_success "服务停止成功"
        else
            print_error "服务停止失败"
            exit 1
        fi
    else
        print_warning "服务未在运行"
    fi
}

# 重启服务
restart_service() {
    check_permission
    print_info "重启 Domain Monitor 服务..."
    stop_service
    start_service
}

# 查看服务状态
show_status() {
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${PURPLE}Domain Monitor 服务状态${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    
    # 服务状态
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo -e "${GREEN}● 服务状态: 运行中${NC}"
        
        # 获取运行时间
        uptime=$(systemctl show ${SERVICE_NAME} --property=ActiveEnterTimestamp | cut -d'=' -f2)
        if [[ -n "$uptime" ]]; then
            echo -e "${WHITE}● 运行时间: ${uptime}${NC}"
        fi
        
        # CPU和内存使用
        pid=$(systemctl show ${SERVICE_NAME} --property=MainPID | cut -d'=' -f2)
        if [[ "$pid" != "0" ]]; then
            if command -v ps &> /dev/null; then
                cpu_mem=$(ps -p $pid -o %cpu,%mem --no-headers 2>/dev/null | tr -s ' ')
                if [[ -n "$cpu_mem" ]]; then
                    cpu=$(echo $cpu_mem | cut -d' ' -f1)
                    mem=$(echo $cpu_mem | cut -d' ' -f2)
                    echo -e "${WHITE}● CPU 使用: ${cpu}%${NC}"
                    echo -e "${WHITE}● 内存使用: ${mem}%${NC}"
                fi
            fi
        fi
    else
        echo -e "${RED}● 服务状态: 已停止${NC}"
    fi
    
    # 配置信息
    if [[ -f "$CONFIG_FILE" ]]; then
        domain_count=$($PYTHON_CMD -c "import json; print(len(json.load(open('$CONFIG_FILE'))['domains']))" 2>/dev/null || echo "0")
        check_interval=$($PYTHON_CMD -c "import json; print(json.load(open('$CONFIG_FILE'))['check_interval'])" 2>/dev/null || echo "3600")
        interval_min=$((check_interval / 60))
        
        echo -e "${WHITE}● 监控域名: ${domain_count} 个${NC}"
        echo -e "${WHITE}● 检查间隔: ${interval_min} 分钟${NC}"
    fi
    
    # 日志信息
    if [[ -f "$LOG_FILE" ]]; then
        log_size=$(du -h "$LOG_FILE" | cut -f1)
        last_check=$(grep "开始检查" "$LOG_FILE" | tail -1 | cut -d' ' -f1-2)
        echo -e "${WHITE}● 日志大小: ${log_size}${NC}"
        if [[ -n "$last_check" ]]; then
            echo -e "${WHITE}● 最后检查: ${last_check}${NC}"
        fi
    fi
    
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
}

# 查看日志
show_logs() {
    if [[ "$1" == "-f" ]] || [[ "$1" == "--follow" ]]; then
        print_info "查看实时日志 (Ctrl+C 退出)..."
        tail -f "$LOG_FILE"
    else
        print_info "显示最近 50 条日志..."
        tail -n 50 "$LOG_FILE"
        echo
        echo -e "${CYAN}提示: 使用 'domainctl logs -f' 查看实时日志${NC}"
    fi
}

# 添加域名
add_domain() {
    check_permission
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        print_error "请指定要添加的域名"
        echo -e "${YELLOW}用法: domainctl add <domain>${NC}"
        exit 1
    fi
    
    # 验证域名格式
    if ! echo "$domain" | grep -qE '^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*; then
        print_error "无效的域名格式: $domain"
        exit 1
    fi
    
    # 添加域名到配置
    $PYTHON_CMD << EOF
import json
config_file = "$CONFIG_FILE"
domain = "$domain"

with open(config_file, 'r') as f:
    config = json.load(f)

if domain in config['domains']:
    print("EXISTS")
else:
    config['domains'].append(domain)
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=4)
    print("ADDED")
EOF

    result=$?
    output=$($PYTHON_CMD << EOF 2>&1
import json
config_file = "$CONFIG_FILE"
domain = "$domain"

with open(config_file, 'r') as f:
    config = json.load(f)

if domain in config['domains']:
    print("EXISTS")
else:
    config['domains'].append(domain)
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=4)
    print("ADDED")
EOF
)
    
    if [[ "$output" == "EXISTS" ]]; then
        print_warning "域名已存在: $domain"
    elif [[ "$output" == "ADDED" ]]; then
        print_success "域名添加成功: $domain"
        
        # 如果服务正在运行，重启服务
        if systemctl is-active --quiet ${SERVICE_NAME}; then
            print_info "重启服务以应用更改..."
            systemctl restart ${SERVICE_NAME}
        fi
    else
        print_error "添加域名失败"
    fi
}

# 删除域名
remove_domain() {
    check_permission
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        print_error "请指定要删除的域名"
        echo -e "${YELLOW}用法: domainctl remove <domain>${NC}"
        exit 1
    fi
    
    # 从配置中删除域名
    output=$($PYTHON_CMD << EOF 2>&1
import json
config_file = "$CONFIG_FILE"
domain = "$domain"

with open(config_file, 'r') as f:
    config = json.load(f)

if domain in config['domains']:
    config['domains'].remove(domain)
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=4)
    print("REMOVED")
else:
    print("NOT_FOUND")
EOF
)
    
    if [[ "$output" == "NOT_FOUND" ]]; then
        print_error "域名不存在: $domain"
    elif [[ "$output" == "REMOVED" ]]; then
        print_success "域名删除成功: $domain"
        
        # 如果服务正在运行，重启服务
        if systemctl is-active --quiet ${SERVICE_NAME}; then
            print_info "重启服务以应用更改..."
            systemctl restart ${SERVICE_NAME}
        fi
    else
        print_error "删除域名失败"
    fi
}

# 列出所有域名
list_domains() {
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${PURPLE}监控域名列表${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "配置文件不存在"
        exit 1
    fi
    
    domains=$($PYTHON_CMD << EOF 2>/dev/null
import json
with open("$CONFIG_FILE", 'r') as f:
    config = json.load(f)
    for i, domain in enumerate(config['domains'], 1):
        print(f"{i}. {domain}")
EOF
)
    
    if [[ -z "$domains" ]]; then
        echo -e "${YELLOW}暂无监控的域名${NC}"
        echo -e "${CYAN}使用 'domainctl add <domain>' 添加域名${NC}"
    else
        echo "$domains"
        echo -e "${CYAN}═══════════════════════════════════════${NC}"
        total=$(echo "$domains" | wc -l)
        echo -e "${WHITE}总计: ${total} 个域名${NC}"
    fi
}

# 立即检查域名
check_domain() {
    local domain="$1"
    
    if [[ -z "$domain" ]]; then
        print_error "请指定要检查的域名"
        echo -e "${YELLOW}用法: domainctl check <domain>${NC}"
        exit 1
    fi
    
    print_info "正在检查域名: $domain"
    
    # 使用 Python 脚本检查域名
    $PYTHON_CMD << EOF
import sys
sys.path.insert(0, "$INSTALL_DIR")
from domain_monitor import DomainMonitor

monitor = DomainMonitor()
result = monitor.check_domain("$domain")

print(f"\\n状态: {result['status'].upper()}")
if result['status'] == 'registered':
    if 'registrar' in result:
        print(f"注册商: {result['registrar']}")
    if 'expiration_date' in result:
        print(f"到期时间: {result['expiration_date']}")
    if 'days_until_expiry' in result:
        print(f"剩余天数: {result['days_until_expiry']} 天")
elif result['status'] == 'available':
    print("\\n✅ 域名可以注册！")
elif result['status'] == 'unknown':
    print(f"错误: {result.get('error', '未知错误')}")
EOF
}

# 生成报告
generate_report() {
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${PURPLE}域名监控报告${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${WHITE}生成时间: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo
    
    # 使用 Python 生成报告
    $PYTHON_CMD << EOF
import json
import os
from datetime import datetime

config_file = "$CONFIG_FILE"
history_file = "${INSTALL_DIR}/data/history.json"

# 加载配置
with open(config_file, 'r') as f:
    config = json.load(f)

# 加载历史
history = {}
if os.path.exists(history_file):
    with open(history_file, 'r') as f:
        history = json.load(f)

# 统计信息
total_domains = len(config['domains'])
available = 0
registered = 0
unknown = 0
expiring_soon = []

print(f"监控域名总数: {total_domains}")
print()

# 分析每个域名
for domain in config['domains']:
    if domain in history and history[domain]:
        last_check = history[domain][-1]
        status = last_check['status']
        
        if status == 'available':
            available += 1
            print(f"✅ {domain} - 可注册")
        elif status == 'registered':
            registered += 1
            details = last_check.get('details', {})
            info = f"❌ {domain} - 已注册"
            
            if 'days_until_expiry' in details:
                days = details['days_until_expiry']
                info += f" (剩余 {days} 天)"
                if days <= 30:
                    expiring_soon.append((domain, days))
            
            print(info)
        else:
            unknown += 1
            print(f"❓ {domain} - 状态未知")
    else:
        print(f"⏳ {domain} - 暂无数据")

print()
print("═" * 39)
print(f"统计摘要:")
print(f"• 可注册: {available} 个")
print(f"• 已注册: {registered} 个")
print(f"• 状态未知: {unknown} 个")

if expiring_soon:
    print()
    print("⚠️  即将到期的域名:")
    for domain, days in sorted(expiring_soon, key=lambda x: x[1]):
        print(f"   • {domain} - {days} 天")
EOF
    
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
}

# 查看配置
show_config() {
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${PURPLE}配置信息${NC}"
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        print_error "配置文件不存在"
        exit 1
    fi
    
    $PYTHON_CMD << EOF
import json

with open("$CONFIG_FILE", 'r') as f:
    config = json.load(f)
    
print(f"Telegram Bot Token: {'*' * 10 + config['telegram']['bot_token'][-10:]}")
print(f"Telegram Chat ID: {config['telegram']['chat_id']}")
print(f"检查间隔: {config['check_interval']} 秒 ({config['check_interval']//60} 分钟)")
print(f"监控域名数: {len(config['domains'])}")
EOF
    
    echo -e "${CYAN}═══════════════════════════════════════${NC}"
    echo -e "${WHITE}配置文件: $CONFIG_FILE${NC}"
}

# 更新程序
update_program() {
    check_permission
    print_info "检查更新..."
    
    # 备份当前文件
    backup_dir="${INSTALL_DIR}/backup_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    print_info "备份当前版本..."
    cp "${INSTALL_DIR}/domain_monitor.py" "$backup_dir/" 2>/dev/null
    cp "/usr/local/bin/domainctl" "$backup_dir/" 2>/dev/null
    
    # 下载新版本
    print_info "下载最新版本..."
    
    # 下载主程序
    if curl -sSL "https://raw.githubusercontent.com/everett7623/domainmonitor/main/domain_monitor.py" -o "${INSTALL_DIR}/domain_monitor.py.new"; then
        mv "${INSTALL_DIR}/domain_monitor.py.new" "${INSTALL_DIR}/domain_monitor.py"
        chmod +x "${INSTALL_DIR}/domain_monitor.py"
        print_success "主程序更新成功"
    else
        print_error "主程序更新失败"
    fi
    
    # 下载管理脚本
    if curl -sSL "https://raw.githubusercontent.com/everett7623/domainmonitor/main/domainctl.sh" -o "/usr/local/bin/domainctl.new"; then
        mv "/usr/local/bin/domainctl.new" "/usr/local/bin/domainctl"
        chmod +x "/usr/local/bin/domainctl"
        print_success "管理脚本更新成功"
    else
        print_error "管理脚本更新失败"
    fi
    
    # 重启服务
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        print_info "重启服务..."
        systemctl restart ${SERVICE_NAME}
    fi
    
    print_success "更新完成！"
}

# 卸载程序
uninstall_program() {
    check_permission
    
    echo -e "${RED}警告: 此操作将完全删除 Domain Monitor！${NC}"
    echo -e "${YELLOW}包括所有配置、日志和历史数据${NC}"
    read -p "确定要继续吗？[y/N]: " confirm
    
    if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
        print_info "取消卸载"
        exit 0
    fi
    
    print_info "停止服务..."
    systemctl stop ${SERVICE_NAME} 2>/dev/null
    systemctl disable ${SERVICE_NAME} 2>/dev/null
    
    print_info "删除文件..."
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    rm -rf "$INSTALL_DIR"
    rm -f "/usr/local/bin/domainctl"
    
    systemctl daemon-reload
    
    print_success "Domain Monitor 已完全卸载"
}

# 主函数
main() {
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
        logs)
            show_logs "$2"
            ;;
        add)
            add_domain "$2"
            ;;
        remove)
            remove_domain "$2"
            ;;
        list)
            list_domains
            ;;
        check)
            check_domain "$2"
            ;;
        report)
            generate_report
            ;;
        config)
            show_config
            ;;
        update)
            update_program
            ;;
        uninstall)
            uninstall_program
            ;;
        help|--help|-h|"")
            show_help
            ;;
        *)
            print_error "未知命令: $1"
            echo -e "${YELLOW}使用 'domainctl help' 查看帮助${NC}"
            exit 1
            ;;
    esac
}

# 运行主函数
main "$@"
