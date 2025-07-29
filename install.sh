#!/bin/bash

#===============================================================================================
# GitHub一键域名到期监控脚本
#===============================================================================================
#
# 功能:
#   - 自动安装依赖 (whois, curl)。
#   - 引导式配置Telegram Bot和初始监控域名。
#   - 通过菜单轻松管理监控列表和配置。
#   - 所有关键操作（如添加/删除）均有Telegram实时通知。
#   - 每日通过Cron自动执行后台监控脚本。
#
# Github用户名: everett7623
# Github仓库名: domainmonitor
#
#===============================================================================================

# --- 脚本变量 ---
# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # 无颜色

# 目录和文件路径
BASE_DIR="$HOME/domainmonitor"
CONFIG_FILE="$BASE_DIR/domains.conf"
TELEGRAM_CONFIG="$BASE_DIR/telegram.conf"
MONITOR_SCRIPT_PATH="$BASE_DIR/monitor.sh"
GITHUB_SCRIPT_URL="https://raw.githubusercontent.com/everett7623/domainmonitor/main/monitor.sh"

# 定时任务 (每天上午9点执行)
CRON_JOB="0 9 * * * $MONITOR_SCRIPT_PATH"

# --- 核心功能函数 ---

# 发送Telegram消息 (此函数在管理脚本中也需要，用于即时反馈)
# 参数1: 消息内容
send_telegram_message() {
    # 检查是否已配置Telegram
    if [ -f "$TELEGRAM_CONFIG" ]; then
        source "$TELEGRAM_CONFIG"
        if [ -n "$TELEGRAM_BOT_TOKEN" ] && [ -n "$TELEGRAM_CHAT_ID" ]; then
            local message="$1"
            # 使用-s静默模式，--max-time设置超时防止脚本卡死
            curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
                -d "chat_id=${TELEGRAM_CHAT_ID}" \
                -d "text=${message}" \
                -d "parse_mode=Markdown" > /dev/null
        fi
    fi
}

# 安装依赖
install_dependencies() {
    echo -e "${YELLOW}正在检查并安装依赖 (curl, whois)...${NC}"
    if command -v apt-get &> /dev/null; then
        apt-get update -y > /dev/null && apt-get install -y curl whois > /dev/null
    elif command -v yum &> /dev/null; then
        yum install -y curl whois > /dev/null
    elif command -v dnf &> /dev/null; then
        dnf install -y curl whois > /dev/null
    else
        echo -e "${RED}无法确定包管理器。请手动安装 'curl' 和 'whois'。${NC}"
        exit 1
    fi
    echo -e "${GREEN}依赖已准备就绪。${NC}"
}

# 添加/更新Telegram Bot通知
configure_telegram() {
    echo -e "${YELLOW}--- 配置Telegram通知 ---${NC}"
    read -rp "请输入您的 Telegram Bot Token: " bot_token
    read -rp "请输入您的 Telegram Chat ID: " chat_id

    # 保存配置
    echo "TELEGRAM_BOT_TOKEN=\"$bot_token\"" > "$TELEGRAM_CONFIG"
    echo "TELEGRAM_CHAT_ID=\"$chat_id\"" >> "$TELEGRAM_CONFIG"

    # 发送测试消息
    echo "正在发送测试消息到你的Telegram..."
    send_telegram_message "✅ *设置成功* ✅\n\n域名监控机器人的Telegram通知已成功配置！"
    
    echo -e "${GREEN}Telegram配置完成！一条测试消息已发送，请检查。${NC}"
}

# 添加监控域名
add_domain() {
    read -rp "请输入要监控的域名 (例如: google.com): " new_domain
    if [ -z "$new_domain" ]; then
        echo -e "${RED}域名不能为空！${NC}"; return;
    fi

    # 检查域名是否已存在
    if grep -q "(\"$new_domain\")" "$CONFIG_FILE"; then
        echo -e "${YELLOW}域名 '$new_domain' 已经存在于监控列表中。${NC}"
        return
    fi
    
    echo "正在获取 '$new_domain' 的信息..."
    local whois_info
    whois_info=$(whois "$new_domain")
    
    # 提取信息
    local expiration_date
    expiration_date=$(echo "$whois_info" | grep -i -E 'Registry Expiry Date:|Expiration Date:|expires:|Expiry Date:' | head -1 | awk -F': ' '{print $2}')
    local creation_date
    creation_date=$(echo "$whois_info" | grep -i -E 'Creation Date:|Registered on:|Registration Time:' | head -1 | awk -F': ' '{print $2}')

    if [ -z "$expiration_date" ]; then
        echo -e "${RED}无法获取域名 '$new_domain' 的信息，请检查域名是否正确。${NC}"
        send_telegram_message "⚠️ *添加失败* ⚠️\n\n无法获取域名 \`$new_domain\` 的信息，请检查后重试。"
        return
    fi
    
    # 将域名添加到配置文件
    # 使用sed，因为直接追加可能导致格式问题
    sed -i "s/DOMAINS_TO_MONITOR=(\(.*\))/DOMAINS_TO_MONITOR=(\1 \"$new_domain\")/" "$CONFIG_FILE"
    
    echo -e "${GREEN}域名 '$new_domain' 添加成功！${NC}"
    
    # 发送Telegram通知
    local message
    message=$(cat <<EOF
✅ *域名添加成功* ✅

已将新域名 \`$new_domain\` 加入监控列表。

*创建日期*: \`$creation_date\`
*到期日期*: \`$expiration_date\`
EOF
)
    send_telegram_message "$message"
}

# 删除监控域名
delete_domain() {
    echo -e "${YELLOW}--- 当前监控的域名列表 ---${NC}"
    # 重新加载并显示列表以便用户选择
    source "$CONFIG_FILE"
    if [ ${#DOMAINS_TO_MONITOR[@]} -eq 0 ]; then
        echo "当前没有监控任何域名。"
        return
    fi
    
    PS3="请输入要删除的域名序号 (输入 q 退出): "
    select domain_to_delete in "${DOMAINS_TO_MONITOR[@]}"; do
        if [[ "$REPLY" == "q" ]]; then break; fi
        if [ -n "$domain_to_delete" ]; then
            # 从配置文件中删除
            sed -i "/\"$domain_to_delete\"/d" "$CONFIG_FILE"
            echo -e "${GREEN}域名 '$domain_to_delete' 已被删除。${NC}"
            send_telegram_message "🗑️ *域名已删除* 🗑️\n\n域名 \`$domain_to_delete\` 已从监控列表中移除。"
            break
        else
            echo -e "${RED}无效的选择。${NC}"
        fi
    done
}

# 查看监控域名
view_domains() {
    echo -e "${YELLOW}--- 当前监控的域名列表 ---${NC}"
    source "$CONFIG_FILE" # 确保加载最新的配置
    if [ ${#DOMAINS_TO_MONITOR[@]} -eq 0 ]; then
        echo "当前没有监控任何域名。"
    else
        for domain in "${DOMAINS_TO_MONITOR[@]}"; do
            echo "- $domain"
        done
    fi
}

# 卸载脚本和配置
uninstall() {
    echo -e "${RED}警告：这将删除所有配置文件、脚本和定时任务。此操作不可逆！${NC}"
    read -rp "您确定要继续吗？(y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        # 删除定时任务
        (crontab -l | grep -v "$MONITOR_SCRIPT_PATH" | crontab -) &>/dev/null
        # 删除文件
        rm -rf "$BASE_DIR"
        echo -e "${GREEN}卸载完成。所有相关文件和定时任务已被清除。${NC}"
        send_telegram_message "👋 *服务已卸载* 👋\n\n域名监控脚本及其所有配置已被移除。"
    else
        echo "卸载已取消。"
    fi
}

# --- 菜单和主程序 ---

# 主菜单
main_menu() {
    clear
    echo "==================================="
    echo "  域名到期监控脚本管理菜单"
    echo "==================================="
    echo -e " 1. ${GREEN}添加监控域名${NC}"
    echo -e " 2. ${RED}删除监控域名${NC}"
    echo -e " 3. ${YELLOW}配置/更新 Telegram Bot${NC}"
    echo -e " 4. ${RED}删除 Telegram Bot 配置${NC}"
    echo -e " 5. ${YELLOW}查看所有监控域名${NC}"
    echo -e " 6. ${RED}卸载并删除所有数据${NC}"
    echo -e " 7. ${YELLOW}退出${NC}"
    echo "-----------------------------------"
    read -rp "请输入您的选择 [1-7]: " choice

    case $choice in
        1) add_domain ;;
        2) delete_domain ;;
        3) configure_telegram ;;
        4) rm -f "$TELEGRAM_CONFIG"; echo -e "${GREEN}Telegram配置已删除。${NC}" ;;
        5) view_domains ;;
        6) uninstall; exit 0 ;;
        7) exit 0 ;;
        *) echo -e "${RED}无效的选项，请输入1-7之间的数字。${NC}" ;;
    esac
    echo ""
    read -rp "按 [Enter] 键返回主菜单..."
    main_menu
}

# 初始化安装流程
initial_install() {
    echo -e "${GREEN}欢迎使用域名到期监控脚本！正在进行首次安装...${NC}"
    
    # 1. 安装依赖
    install_dependencies
    
    # 2. 创建目录结构
    mkdir -p "$BASE_DIR"
    
    # 3. 创建空的域名配置文件
    echo "# 域名监控列表" > "$CONFIG_FILE"
    echo "DOMAINS_TO_MONITOR=()" >> "$CONFIG_FILE"
    
    # 4. 下载后台监控脚本
    echo "正在从GitHub下载最新的监控脚本..."
    if ! curl -sSL "$GITHUB_SCRIPT_URL" -o "$MONITOR_SCRIPT_PATH"; then
        echo -e "${RED}下载监控脚本失败！请检查网络或URL。${NC}"
        exit 1
    fi
    chmod +x "$MONITOR_SCRIPT_PATH"
    
    # 5. 配置Telegram
    configure_telegram
    
    # 6. 添加第一个域名
    echo -e "${YELLOW}--- 添加您的第一个监控域名 ---${NC}"
    add_domain
    
    # 7. 设置定时任务
    echo "正在设置每日自动检查的定时任务..."
    (crontab -l 2>/dev/null | grep -v "$MONITOR_SCRIPT_PATH"; echo "$CRON_JOB") | crontab -
    
    echo -e "${GREEN}🎉 恭喜！安装和配置全部完成！🎉${NC}"
    echo "脚本将每日上午9点自动检查域名状态。您现在将进入主管理菜单。"
    echo ""
    read -rp "按 [Enter] 键进入主菜单..."
    main_menu
}

# --- 脚本入口 ---
# 检查是否以root权限运行
if [ "$(id -u)" -eq 0 ]; then
    echo -e "${YELLOW}警告：建议不要以root用户身份直接运行此脚本。${NC}"
    echo "脚本将在当前用户（root）的主目录下创建文件。"
    read -rp "您确定要继续吗？(y/n): " root_confirm
    if [[ ! "$root_confirm" =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# 如果是首次运行（判断标准是主目录是否存在），则执行安装流程
if [ ! -d "$BASE_DIR" ]; then
    initial_install
else
    main_menu
fi
