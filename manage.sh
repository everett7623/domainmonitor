#!/bin/bash

# ==============================================================================
# GitHub: everett7623/domainmonitor
#
# 功能: 提供一个简单的命令行菜单来管理域名监控列表和配置
#
# ==============================================================================

# 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 确保在脚本所在目录执行
cd "$(dirname "$0")" || exit

DOMAINS_FILE="domains.txt"
CONFIG_FILE="config.ini"
INSTALL_DIR=$(pwd)

# --- 功能函数 ---

add_domain() {
    echo -e "${YELLOW}请输入要添加的域名 (例如: newdomain.com):${NC}"
    read -r new_domain
    if [ -z "$new_domain" ]; then
        echo -e "${RED}域名不能为空!${NC}"
        return
    fi
    # 检查域名是否已存在
    if grep -qxF "$new_domain" "$DOMAINS_FILE"; then
        echo -e "${RED}域名 '$new_domain' 已存在于监控列表中。${NC}"
    else
        echo "$new_domain" >> "$DOMAINS_FILE"
        echo -e "${GREEN}成功添加域名: $new_domain${NC}"
    fi
}

delete_domain() {
    if [ ! -s "$DOMAINS_FILE" ]; then
        echo -e "${RED}域名列表为空，无需删除。${NC}"
        return
    fi

    echo -e "${YELLOW}当前监控的域名列表:${NC}"
    # 显示带行号的列表
    nl -w2 -s'. ' "$DOMAINS_FILE"
    echo -e "${YELLOW}请输入要删除的域名前面的数字编号:${NC}"
    read -r num
    # 验证输入是否为数字
    if ! [[ "$num" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}输入无效，请输入数字。${NC}"
        return
    fi

    # 获取总行数
    total_lines=$(wc -l < "$DOMAINS_FILE")
    if [ "$num" -gt "$total_lines" ] || [ "$num" -lt 1 ]; then
        echo -e "${RED}无效的编号。${NC}"
        return
    fi

    domain_to_delete=$(sed -n "${num}p" "$DOMAINS_FILE")
    # 使用sed删除指定行
    sed -i.bak "${num}d" "$DOMAINS_FILE"
    echo -e "${GREEN}成功删除域名: $domain_to_delete${NC}"
}

update_telegram() {
    echo -e "${YELLOW}将重新设置 Telegram 信息。${NC}"
    echo "请输入新的 Telegram Bot Token:"
    read -r new_bot_token
    while [ -z "$new_bot_token" ]; do
        echo -e "${RED}Bot Token 不能为空!${NC}"
        read -r -p "Bot Token: " new_bot_token
    done

    echo "请输入新的 Telegram Chat ID:"
    read -r new_chat_id
    while [ -z "$new_chat_id" ]; do
        echo -e "${RED}Chat ID 不能为空!${NC}"
        read -r -p "Chat ID: " new_chat_id
    done
    
    # 使用sed更新配置文件
    sed -i.bak "s/^bot_token = .*/bot_token = $new_bot_token/" "$CONFIG_FILE"
    sed -i.bak "s/^chat_id = .*/chat_id = $new_chat_id/" "$CONFIG_FILE"
    
    echo -e "${GREEN}Telegram 信息已更新!${NC}"
}


view_domains() {
    echo -e "${CYAN}--- 当前监控的域名 ---${NC}"
    if [ -s "$DOMAINS_FILE" ]; then
        cat "$DOMAINS_FILE"
    else
        echo "列表为空"
    fi
    echo "--------------------------"
}

uninstall() {
    echo -e "${RED}警告: 这个操作将删除所有脚本文件和定时任务!${NC}"
    read -r -p "你确定要卸载吗? (y/n): " confirm
    if [[ "$confirm" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        echo "正在删除 Cron 定时任务..."
        (crontab -l 2>/dev/null | grep -v "$INSTALL_DIR/domain_monitor.py") | crontab -
        
        echo "正在删除项目目录: $INSTALL_DIR..."
        rm -rf "$INSTALL_DIR"
        
        echo -e "${GREEN}Domain Monitor 已成功卸载。${NC}"
        exit 0
    else
        echo "卸载已取消。"
    fi
}


# --- 主菜单 ---

show_menu() {
    clear
    echo -e "${CYAN}=============================${NC}"
    echo -e "${CYAN}  Domain Monitor 管理菜单  ${NC}"
    echo -e "${CYAN}=============================${NC}"
    echo " [1] 添加监控域名"
    echo " [2] 删除监控域名"
    echo " [3] 查看监控域名"
    echo " [4] 更新 Telegram Bot 通知"
    echo "-----------------------------"
    echo -e " [${RED}9${NC}] 卸载监控脚本"
    echo " [0] 退出"
    echo "============================="
    echo -e "${YELLOW}请输入你的选择 [0-9]:${NC}"
}

while true; do
    show_menu
    read -r choice
    case $choice in
        1) add_domain ;;
        2) delete_domain ;;
        3) view_domains ;;
        4) update_telegram ;;
        9) uninstall ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效的选择, 请重试。${NC}" ;;
    esac
    echo -e "\n${YELLOW}按 Enter键 返回主菜单...${NC}"
    read -r
done
