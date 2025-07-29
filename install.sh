#!/bin/bash

#----------------------------------------------------------------
# 脚本：install.sh
# 功能：一键安装、配置和管理域名到期监控
# 作者：Gemini
# 用户名：everett7623
# 仓库名：domainmonitor
#----------------------------------------------------------------

# 变量
GITHUB_USER="everett7623"
GITHUB_REPO="domainmonitor"
SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main/monitor.sh"
CONFIG_FILE="$HOME/.domain_monitor.conf"
TELEGRAM_CONFIG="$HOME/.telegram.conf"
CRON_JOB="0 9 * * * $HOME/domainmonitor/monitor.sh" # 每天上午9点执行

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 检查是否以 root 权限运行
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}此脚本必须以 root 权限运行。${NC}" 1>&2
   exit 1
fi

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在安装依赖 (curl, whois)...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update > /dev/null
        apt-get install -y curl whois > /dev/null
    elif command -v yum &> /dev/null; then
        yum install -y curl whois > /dev/null
    else
        echo -e "${RED}不支持的包管理器。请手动安装 'curl' 和 'whois'。${NC}"
        exit 1
    fi
    echo -e "${GREEN}依赖安装完成。${NC}"
}

# 添加监控域名
add_domain() {
    read -rp "请输入要监控的域名: " new_domain
    if ! grep -q "$new_domain" "$CONFIG_FILE"; then
        echo "DOMAINS_TO_MONITOR+=(\"$new_domain\")" >> "$CONFIG_FILE"
        echo -e "${GREEN}域名 '$new_domain' 添加成功。${NC}"
    else
        echo -e "${YELLOW}域名 '$new_domain' 已存在。${NC}"
    fi
}

# 删除监控域名
delete_domain() {
    read -rp "请输入要删除的域名: " domain_to_delete
    sed -i "/$domain_to_delete/d" "$CONFIG_FILE"
    echo -e "${GREEN}域名 '$domain_to_delete' 删除成功。${NC}"
}

# 添加 Telegram Bot 通知
add_telegram() {
    read -rp "请输入您的 Telegram Bot Token: " bot_token
    read -rp "请输入您的 Telegram Chat ID: " chat_id
    echo "TELEGRAM_BOT_TOKEN=\"$bot_token\"" > "$TELEGRAM_CONFIG"
    echo "TELEGRAM_CHAT_ID=\"$chat_id\"" >> "$TELEGRAM_CONFIG"
    echo -e "${GREEN}Telegram Bot 配置成功。${NC}"
}

# 删除 Telegram Bot 通知
delete_telegram() {
    rm -f "$TELEGRAM_CONFIG"
    echo -e "${GREEN}Telegram Bot 配置已删除。${NC}"
}

# 查看监控域名
view_domains() {
    echo -e "${YELLOW}当前监控的域名列表：${NC}"
    source "$CONFIG_FILE"
    for domain in "${DOMAINS_TO_MONITOR[@]}"; do
        echo "- $domain"
    done
}

# 删除监控域名和脚本
uninstall() {
    echo -e "${RED}警告：这将删除所有配置文件、脚本和定时任务。${NC}"
    read -rp "您确定要继续吗？(y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        crontab -l | grep -v "$CRON_JOB" | crontab -
        rm -rf "$HOME/domainmonitor"
        rm -f "$CONFIG_FILE" "$TELEGRAM_CONFIG"
        echo -e "${GREEN}卸载完成。${NC}"
    else
        echo "卸载已取消。"
    fi
}

# 主菜单
main_menu() {
    clear
    echo "==================================="
    echo " 域名到期监控脚本"
    echo "==================================="
    echo "1. 添加监控域名"
    echo "2. 删除监控域名"
    echo "3. 添加 Telegram Bot 通知"
    echo "4. 删除 Telegram Bot 通知"
    echo "5. 查看监控域名"
    echo "6. 删除监控域名和脚本"
    echo "7. 退出"
    echo "-----------------------------------"
    read -rp "请输入您的选择 [1-7]: " choice
    
    case $choice in
        1) add_domain ;;
        2) delete_domain ;;
        3) add_telegram ;;
        4) delete_telegram ;;
        5) view_domains ;;
        6) uninstall ;;
        7) exit 0 ;;
        *) echo -e "${RED}无效的选项。${NC}" ;;
    esac
    read -rp "按 Enter 键返回主菜单..."
    main_menu
}

# 初始化安装
initial_install() {
    install_dependencies
    
    mkdir -p "$HOME/domainmonitor"
    curl -sSL "$SCRIPT_URL" -o "$HOME/domainmonitor/monitor.sh"
    chmod +x "$HOME/domainmonitor/monitor.sh"
    
    if [ ! -f "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
        echo "DOMAINS_TO_MONITOR=()" > "$CONFIG_FILE"
    fi
    
    if [ ! -f "$TELEGRAM_CONFIG" ]; then
        add_telegram
    fi
    
    (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
    
    echo -e "${GREEN}安装成功！已设置每日定时检查。${NC}"
    main_menu
}

# 如果是首次运行，则执行安装
if [ ! -d "$HOME/domainmonitor" ]; then
    initial_install
else
    main_menu
fi
