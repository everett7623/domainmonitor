#!/bin/bash
# ================================================================================
# DomainMonitor 管理脚本
# 
# 作者: everett7623
# GitHub: https://github.com/everett7623/domainmonitor
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
    echo -e "${CYAN}DomainMonitor 管理工具${NC}"
    echo
    echo "使用方法: domainctl [命令] [参数]"
    echo
    echo "命令列表:"
    echo -e "  ${GREEN}start${NC}      启动监控服务"
    echo -e "  ${GREEN}stop${NC}       停止监控服务"
    echo -e "  ${GREEN}restart${NC}    重启监控服务"
    echo -e "  ${GREEN}status${NC}     查看服务状态"
    echo -e "  ${GREEN}add${NC}        添加监控域名"
    echo -e "  ${GREEN}remove${NC}     删除监控域名"
    echo -e "  ${GREEN}list${NC}       列出所有监控域名"
    echo -e "  ${GREEN}check${NC}      立即检查所有域名"
    echo -e "  ${GREEN}logs${NC}       查看日志"
    echo -e "  ${GREEN}config${NC}     编辑配置文件"
    echo -e "  ${GREEN}update${NC}     更新程序"
    echo -e "  ${GREEN}uninstall${NC}  卸载程序"
    echo
    echo "示例:"
    echo -e "  ${CYAN}domainctl add example.com${NC}"
    echo -e "  ${CYAN}domainctl remove example.com${NC}"
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
    echo -e "${BLUE}▶ 监控域名统计${NC}"
    if [[ -f "$CONFIG_FILE" ]]; then
        DOMAIN_COUNT=$(cat "$CONFIG_FILE" | jq -r '.domains | length')
        echo -e "监控域名数: ${GREEN}${DOMAIN_COUNT}${NC}"
    fi
    
    echo
    echo -e "${BLUE}▶ 最近日志${NC}"
    tail -n 10 "$INSTALL_DIR/logs/domainmonitor.log"
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
    
    # 使用 Python 脚本添加域名
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
    
    # 如果服务正在运行，重启以应用更改
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
    
    # 使用 Python 脚本删除域名
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
    
    # 如果服务正在运行，重启以应用更改
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${CYAN}正在重启服务以应用更改...${NC}"
        systemctl restart $SERVICE_NAME
    fi
}

# 列出域名
list_domains() {
    echo -e "${BLUE}▶ 监控域名列表${NC}"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${RED}错误: 配置文件不存在${NC}"
        exit 1
    fi
    
    # 使用 jq 解析 JSON
    if command -v jq &> /dev/null; then
        domains=$(cat "$CONFIG_FILE" | jq -r '.domains[]' 2>/dev/null)
        
        if [[ -z "$domains" ]]; then
            echo -e "${YELLOW}暂无监控域名${NC}"
        else
            echo "$domains" | nl -w 3 -s '. '
        fi
    else
        # 如果没有 jq，使用 Python
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
    fi
}

# 立即检查
check_now() {
    echo -e "${BLUE}▶ 立即检查所有域名${NC}"
    
    cd "$INSTALL_DIR"
    source venv/bin/activate
    
    # 创建一次性检查脚本
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
    curl -sSL "https://raw.githubusercontent.com/everett7623/domainmonitor/main/domainmonitor.py" -o domainmonitor.py.new
    curl -sSL "https://raw.githubusercontent.com/everett7623/domainmonitor/main/domainctl.sh" -o domainctl.sh.new
    
    # 备份当前版本
    cp domainmonitor.py domainmonitor.py.bak
    cp domainctl.sh domainctl.sh.bak
    
    # 替换文件
    mv domainmonitor.py.new domainmonitor.py
    mv domainctl.sh.new domainctl.sh
    chmod +x domainmonitor.py domainctl.sh
    
    echo -e "${GREEN}✓ 更新完成${NC}"
    
    # 重启服务
    if systemctl is-active --quiet $SERVICE_NAME; then
        restart_service
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
