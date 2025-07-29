#!/bin/bash
# =====================================================
# 域名到期监控脚本
# 功能：监控域名到期时间并通过Telegram通知
# 作者：everett7623
# 仓库：https://github.com/everett7623/domainmonitor
# =====================================================

# 配置文件路径
CONFIG_FILE="$HOME/.domain_monitor.conf"
LOG_FILE="$HOME/domain_monitor.log"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # 恢复默认

# 初始化配置文件
init_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
        echo "DOMAINS=()" > "$CONFIG_FILE"
        echo "TELEGRAM_BOT_TOKEN=" >> "$CONFIG_FILE"
        echo "TELEGRAM_CHAT_ID=" >> "$CONFIG_FILE"
    fi
}

# 加载配置
load_config() {
    source "$CONFIG_FILE" 2>/dev/null
}

# 保存配置
save_config() {
    cat > "$CONFIG_FILE" <<EOF
DOMAINS=(${DOMAINS[@]})
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
EOF
}

# 发送Telegram通知
send_telegram() {
    local message="$1"
    if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
        curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
             -d chat_id="$TELEGRAM_CHAT_ID" \
             -d text="$message" > /dev/null
    fi
}

# 添加域名
add_domain() {
    echo -e "${BLUE}请输入要监控的域名（例如：example.com）：${NC}"
    read domain
    if [[ " ${DOMAINS[@]} " =~ " ${domain} " ]]; then
        echo -e "${RED}错误：域名 $domain 已在监控列表中！${NC}"
        return 1
    fi
    DOMAINS+=("$domain")
    save_config
    echo -e "${GREEN}已添加域名 $domain 到监控列表！${NC}"
    send_telegram "已添加域名 $domain 到监控列表！"
}

# 删除域名
remove_domain() {
    if [ ${#DOMAINS[@]} -eq 0 ]; then
        echo -e "${RED}错误：监控列表为空！${NC}"
        return 1
    fi
    echo -e "${BLUE}当前监控的域名：${NC}"
    for ((i=0; i<${#DOMAINS[@]}; i++)); do
        echo -e "${YELLOW}$((i+1)). ${DOMAINS[$i]}${NC}"
    done
    echo -e "${BLUE}请输入要删除的域名编号：${NC}"
    read choice
    if [[ ! $choice =~ ^[0-9]+$ ]] || [ $choice -lt 1 ] || [ $choice -gt ${#DOMAINS[@]} ]; then
        echo -e "${RED}错误：无效的选择！${NC}"
        return 1
    fi
    removed_domain=${DOMAINS[$((choice-1))]}
    DOMAINS=(${DOMAINS[@]:0:$((choice-1))} ${DOMAINS[@]:$choice})
    save_config
    echo -e "${GREEN}已从监控列表中删除域名 $removed_domain！${NC}"
    send_telegram "已从监控列表中删除域名 $removed_domain！"
}

# 添加Telegram Bot
add_telegram() {
    echo -e "${BLUE}请输入Telegram Bot Token：${NC}"
    read token
    echo -e "${BLUE}请输入接收通知的Chat ID：${NC}"
    read chat_id
    TELEGRAM_BOT_TOKEN="$token"
    TELEGRAM_CHAT_ID="$chat_id"
    save_config
    echo -e "${GREEN}已配置Telegram通知！${NC}"
    send_telegram "Telegram通知已配置成功！"
}

# 删除Telegram Bot
remove_telegram() {
    TELEGRAM_BOT_TOKEN=""
    TELEGRAM_CHAT_ID=""
    save_config
    echo -e "${GREEN}已删除Telegram通知配置！${NC}"
}

# 查看域名列表
list_domains() {
    if [ ${#DOMAINS[@]} -eq 0 ]; then
        echo -e "${RED}监控列表为空！${NC}"
        return 1
    fi
    echo -e "${BLUE}当前监控的域名：${NC}"
    for ((i=0; i<${#DOMAINS[@]}; i++)); do
        echo -e "${YELLOW}$((i+1)). ${DOMAINS[$i]}${NC}"
    done
}

# 删除脚本和配置
uninstall() {
    echo -e "${RED}警告：这将删除所有监控配置和脚本文件！${NC}"
    echo -e "${BLUE}是否继续？(y/N) ${NC}"
    read confirm
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        echo -e "${GREEN}操作已取消！${NC}"
        return 1
    fi
    rm -f "$CONFIG_FILE" "$LOG_FILE"
    echo -e "${GREEN}已成功删除域名监控脚本和配置！${NC}"
    exit 0
}

# 显示菜单
show_menu() {
    clear
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${GREEN}         域名到期监控脚本          ${NC}"
    echo -e "${GREEN}=====================================${NC}"
    echo -e "${BLUE}1. 添加监控域名${NC}"
    echo -e "${BLUE}2. 删除监控域名${NC}"
    echo -e "${BLUE}3. 添加Telegram Bot通知${NC}"
    echo -e "${BLUE}4. 删除Telegram Bot通知${NC}"
    echo -e "${BLUE}5. 查看监控域名${NC}"
    echo -e "${BLUE}6. 删除监控域名和脚本${NC}"
    echo -e "${BLUE}7. 退出${NC}"
    echo -e "${GREEN}-------------------------------------${NC}"
    echo -e "${BLUE}请输入你的选择 [1-7]: ${NC}"
}

# 主程序
init_config
load_config

while true; do
    show_menu
    read choice
    case $choice in
        1) add_domain ;;
        2) remove_domain ;;
        3) add_telegram ;;
        4) remove_telegram ;;
        5) list_domains ;;
        6) uninstall ;;
        7) echo -e "${GREEN}感谢使用域名监控脚本，再见！${NC}"; exit 0 ;;
        *) echo -e "${RED}错误：无效的选择，请输入1-7之间的数字！${NC}" ;;
    esac
    echo -e "${BLUE}按Enter键继续...${NC}"
    read
done    
