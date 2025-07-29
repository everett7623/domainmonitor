#!/bin/bash
# =================================================================
# Project: Domain Expiration Monitor (v1.2)
# Author: Everett7623
# GitHub: https://github.com/everett7623/domainmonitor
# Description: 此脚本为一键安装脚本，用于设置域名到期监控和Telegram通知。
#              它具备菜单交互功能，方便用户输入相关信息，同时会自动检查并安装依赖。
#              配置完成后，会生成监控脚本并设置定时任务，确保域名到期能及时通知。
# =================================================================

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 欢迎信息
echo -e "${GREEN}欢迎使用域名到期监控脚本！${NC}"
echo "此脚本将引导您完成设置。"
echo ""

# --- 新增：依赖检查与自动安装 ---
check_and_install_dependencies() {
    echo "正在检查所需依赖..."
    local missing_packages=""
    if ! command -v whois &> /dev/null; then
        missing_packages="whois"
    fi
    if ! command -v curl &> /dev/null; then
        missing_packages="$missing_packages curl"
    fi

    if [ -n "$missing_packages" ]; then
        echo -e "${YELLOW}检测到以下必需的命令未安装: $missing_packages${NC}"
        
        # 检测包管理器
        local package_manager=""
        if command -v apt-get &> /dev/null; then
            package_manager="apt-get"
        elif command -v yum &> /dev/null; then
            package_manager="yum"
        else
            echo -e "${RED}无法检测到 apt-get 或 yum。请手动安装: $missing_packages 然后重新运行脚本。${NC}"
            exit 1
        fi

        read -p "是否尝试自动为您安装？ (y/n): " confirm
        if [[ "$confirm" == [yY] || "$confirm" == [yY][eE][sS] ]]; then
            echo "正在使用 $package_manager 安装..."
            if [ "$package_manager" == "apt-get" ]; then
                sudo apt-get update && sudo apt-get install -y $missing_packages
            else
                sudo yum install -y $missing_packages
            fi

            if [ $? -ne 0 ]; then
                echo -e "${RED}依赖安装失败。请检查您的系统或手动安装后重试。${NC}"
                exit 1
            fi
            echo -e "${GREEN}依赖安装成功！${NC}"
        else
            echo -e "${RED}用户取消。请在安装依赖后重新运行脚本。${NC}"
            exit 1
        fi
    else
        echo -e "${GREEN}所有依赖均已满足。${NC}"
    fi
    echo ""
}
# ------------------------------------

# 执行依赖检查
check_and_install_dependencies

# 变量初始化
DOMAINS=""
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""
EXPIRY_THRESHOLD=30 # 默认提前30天提醒

# 域名设置函数
set_domains() {
    echo ""
    echo "请输入您要监控的域名，多个域名请用空格隔开。"
    echo "例如: google.com github.com"
    while true; do
        read -p "域名列表: " -a DOMAIN_ARRAY
        DOMAINS=$(IFS=" "; echo "${DOMAIN_ARRAY[*]}")
        if [ -z "$DOMAINS" ]; then
            echo -e "${RED}域名列表不能为空！请重新输入。${NC}"
        else
            echo -e "${GREEN}域名已设置为: $DOMAINS${NC}"
            sleep 2
            break
        fi
    done
}

# Telegram设置函数
set_telegram() {
    echo ""
    while true; do
        echo "请输入您的 Telegram Bot Token:"
        read -p "Bot Token: " TELEGRAM_BOT_TOKEN
        echo ""
        echo "请输入您的 Telegram Chat ID:"
        read -p "Chat ID: " TELEGRAM_CHAT_ID
        echo ""
        echo "请输入您希望提前多少天收到通知（默认为30天）:"
        read -p "提前通知天数 [默认30]: " threshold_input
        if [ -n "$threshold_input" ]; then
            EXPIRY_THRESHOLD=$threshold_input
        fi

        if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
            echo -e "${RED}Bot Token 和 Chat ID 不能为空！请重新输入。${NC}"
        else
            echo -e "${GREEN}Telegram 设置成功！将提前 $EXPIRY_THRESHOLD 天通知。${NC}"
            sleep 2
            break
        fi
    done
}

# 安装函数
install() {
    if [ -z "$DOMAINS" ] || [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo -e "${RED}错误：域名或Telegram信息未设置。请先完成设置。${NC}"
        sleep 3
        return
    fi

    echo "正在创建监控脚本 monitor.sh..."
    # 将配置写入 monitor.sh
    cat > monitor.sh <<- EOM
#!/bin/bash

# =================================================================
# Project: Domain Expiration Monitor (Core Script)
# Author: Everett7623
# GitHub: https://github.com/everett7623/domainmonitor
# =================================================================

# --- 从install.sh传入的配置 ---
DOMAINS_TO_CHECK="$DOMAINS"
TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
EXPIRY_THRESHOLD=$EXPIRY_THRESHOLD
# --------------------------------

# 发送Telegram消息的函数
send_telegram_message() {
    local message=\$1
    # 使用 --connect-timeout 避免长时间卡住
    curl -s -X POST "https://api.telegram.org/bot\${TELEGRAM_BOT_TOKEN}/sendMessage" \\
        --connect-timeout 10 \\
        -d chat_id="\${TELEGRAM_CHAT_ID}" \\
        -d text="\${message}" \\
        -d parse_mode="Markdown" > /dev/null
}

# 主逻辑
LOG_FILE="\$(dirname "\$0")/monitor.log"
echo "[\$(date)] 开始检查域名到期时间..." >> "\$LOG_FILE"

for domain in \$DOMAINS_TO_CHECK; do
    # 使用whois获取信息，并过滤出过期日期
    # 注意：不同注册商返回的格式可能不同，这里使用通用的 "Expiration Date" 和 "Registry Expiry Date"
    expiry_date_str=\$(whois \$domain | grep -i -E "Expiration Date|Registry Expiry Date" | head -n 1 | sed -e 's/.*: //')

    if [ -z "\$expiry_date_str" ]; then
        echo "[\$(date)] 无法获取 \$domain 的到期日期。" >> "\$LOG_FILE"
        send_telegram_message "⚠️ *域名监控警告* ⚠️\n\n无法获取域名 \`\$domain\` 的到期日期，请手动检查！"
        continue
    fi
    
    # 兼容 GNU date 和 BSD date
    expiry_seconds=""
    if date --version >/dev/null 2>&1; then
        expiry_seconds=\$(date -d "\$expiry_date_str" +%s 2>/dev/null)
    else
        expiry_seconds=\$(date -jf "%Y-%m-%dT%H:%M:%SZ" "\$expiry_date_str" +%s 2>/dev/null) || \\
        expiry_seconds=\$(date -jf "%d-%b-%Y" "\$expiry_date_str" +%s 2>/dev/null) # 兼容 "01-Jan-2025" 格式
    fi

    if [ -z "\$expiry_seconds" ]; then
        echo "[\$(date)] 无法解析 \$domain 的日期字符串: \$expiry_date_str" >> "\$LOG_FILE"
        send_telegram_message "⚠️ *域名监控警告* ⚠️\n\n无法解析域名 \`\$domain\` 的到期日期格式 (\`\$expiry_date_str\`)，请手动检查！"
        continue
    fi
    
    current_seconds=\$(date +%s)
    days_left=\$(((expiry_seconds - current_seconds) / 86400))

    echo "[\$(date)] 域名: \$domain, 剩余天数: \$days_left" >> "\$LOG_FILE"

    if [ \$days_left -le \$EXPIRY_THRESHOLD ]; then
        message="🚨 *域名到期提醒* 🚨\n\n域名: \`\$domain\`\n即将在 *\$days_left 天* 后到期！\n到期日期: \`\$(date -d "@\$expiry_seconds" '+%Y-%m-%d')\`\n\n请尽快续费！"
        send_telegram_message "\$message"
        echo "[\$(date)] 已为 \$domain 发送到期提醒到 Telegram。" >> "\$LOG_FILE"
    fi
    # whois查询之间增加延迟，防止被服务器屏蔽
    sleep 3
done

echo "[\$(date)] 所有域名检查完毕。" >> "\$LOG_FILE"
echo "" >> "\$LOG_FILE"

EOM

    # 赋予执行权限
    chmod +x monitor.sh
    echo -e "${GREEN}monitor.sh 创建成功！${NC}"

    # 设置Cron Job
    echo "正在设置定时任务 (Cron Job)..."
    # 清理旧的定时任务，添加新的
    (crontab -l 2>/dev/null | grep -v "domainmonitor/monitor.sh" ; echo "0 9 * * * cd $(pwd) && /bin/bash $(pwd)/monitor.sh") | crontab -

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}定时任务设置成功！脚本将每天上午9点自动运行。${NC}"
        echo "日志文件将保存在 $(pwd)/monitor.log"
    else
        echo -e "${RED}设置定时任务失败。请手动设置。${NC}"
        echo "请将以下内容添加到您的 crontab 中:"
        echo "0 9 * * * cd $(pwd) && /bin/bash $(pwd)/monitor.sh"
    fi

    echo ""
    echo -e "${GREEN}🎉 全部设置完成！ 🎉${NC}"
    echo "你可以运行 'bash monitor.sh' 来立即测试一次。"
    exit 0
}

# 菜单函数
show_menu() {
    clear
    echo "=============================="
    echo "   域名到期监控设置"
    echo "=============================="
    echo "1. 设置要监控的域名"
    echo "2. 设置Telegram Bot通知"
    echo "3. 完成并安装"
    echo "4. 退出"
    echo "=============================="
}

# 主循环
while true; do
    show_menu
    read -p "请输入您的选择 [1-4]: " choice
    case $choice in
        1)
            set_domains
            ;;
        2)
            set_telegram
            ;;
        3)
            install
            ;;
        4)
            echo "退出安装。"
            exit 0
            ;;
        *)
            echo -e "${RED}无效的输入，请输入 1-4 之间的数字。${NC}"
            read -p "按回车键继续..."
            ;;
    esac
done
