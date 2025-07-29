#!/bin/bash

# =================================================================
# Project: Domain Expiration Monitor
# Author: Everett7623
# GitHub: https://github.com/everett7623/domainmonitor
# Description: 一键安装脚本，用于设置域名到期监控和Telegram通知。
# =================================================================

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# 欢迎信息
echo -e "${GREEN}欢迎使用域名到期监控脚本！${NC}"
echo "此脚本将引导您完成设置。"
echo ""

# 检查依赖 (whois 和 curl)
if ! command -v whois &> /dev/null
then
    echo -e "${RED}错误: 'whois' 命令未找到。请先安装它。${NC}"
    echo "在 Debian/Ubuntu 上，请运行: sudo apt-get update && sudo apt-get install whois"
    echo "在 CentOS/RHEL 上，请运行: sudo yum install whois"
    exit 1
fi

if ! command -v curl &> /dev/null
then
    echo -e "${RED}错误: 'curl' 命令未找到。请先安装它。${NC}"
    echo "在 Debian/Ubuntu 上，请运行: sudo apt-get update && sudo apt-get install curl"
    echo "在 CentOS/RHEL 上，请运行: sudo yum install curl"
    exit 1
fi

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
    read -p "域名列表: " -a DOMAIN_ARRAY
    DOMAINS=$(IFS=" "; echo "${DOMAIN_ARRAY[*]}")
    if [ -z "$DOMAINS" ]; then
        echo -e "${RED}域名列表不能为空！${NC}"
        sleep 2
    else
        echo -e "${GREEN}域名已设置为: $DOMAINS${NC}"
        sleep 2
    fi
}

# Telegram设置函数
set_telegram() {
    echo ""
    echo "请输入您的 Telegram Bot Token:"
    read -p "Bot Token: " TELEGRAM_BOT_TOKEN
    echo ""
    echo "请输入您的 Telegram Chat ID:"
    read -p "Chat ID: " TELEGRAM_CHAT_ID
    echo ""
    echo "请输入您希望提前多少天收到通知（默认为30天）:"
    read -p "提前通知天数: " -i "30" -e EXPIRY_THRESHOLD

    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
        echo -e "${RED}Bot Token 和 Chat ID 不能为空！${NC}"
        sleep 2
    else
        echo -e "${GREEN}Telegram 设置成功！${NC}"
        sleep 2
    fi
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
    curl -s -X POST "https://api.telegram.org/bot\${TELEGRAM_BOT_TOKEN}/sendMessage" \\
        -d chat_id="\${TELEGRAM_CHAT_ID}" \\
        -d text="\${message}" \\
        -d parse_mode="Markdown" > /dev/null
}

# 主逻辑
echo "开始检查域名到期时间..."
for domain in \$DOMAINS_TO_CHECK; do
    echo "正在检查: \$domain"
    
    # 使用whois获取信息，并过滤出过期日期
    # 注意：不同注册商返回的格式可能不同，这里使用通用的 "Expiration Date"
    expiry_date_str=\$(whois \$domain | grep -i "Expiration Date\|Registry Expiry Date" | head -n 1 | awk -F': ' '{print \$2}')

    if [ -z "\$expiry_date_str" ]; then
        echo "无法获取 \$domain 的到期日期。"
        send_telegram_message "⚠️ *域名监控警告* ⚠️\n\n无法获取域名 \`\$domain\` 的到期日期，请手动检查！"
        continue
    fi
    
    # 转换日期为秒数以便比较
    # for GNU date
    if date --version >/dev/null 2>&1; then
        expiry_seconds=\$(date -d "\$expiry_date_str" +%s)
        current_seconds=\$(date +%s)
    # for BSD date (macOS)
    else
        expiry_seconds=\$(date -jf "%Y-%m-%dT%H:%M:%SZ" "\$expiry_date_str" +%s)
        current_seconds=\$(date +%s)
    fi

    days_left=\$(((expiry_seconds - current_seconds) / 86400))

    echo "域名: \$domain, 剩余天数: \$days_left"

    if [ \$days_left -le \$EXPIRY_THRESHOLD ]; then
        message="🚨 *域名到期提醒* 🚨\n\n域名: \`\$domain\`\n即将在 *\$days_left 天* 后到期！\n到期日期: `date -d @\$expiry_seconds '+%Y-%m-%d'`\n\n请尽快续费！"
        send_telegram_message "\$message"
        echo "已发送到期提醒到 Telegram。"
    fi
    # whois查询之间增加延迟，防止被服务器屏蔽
    sleep 3
done

echo "所有域名检查完毕。"

EOM

    # 赋予执行权限
    chmod +x monitor.sh
    echo -e "${GREEN}monitor.sh 创建成功！${NC}"

    # 设置Cron Job
    echo "正在设置定时任务 (Cron Job)..."
    # (crontab -l 2>/dev/null; echo "0 9 * * * /bin/bash $(pwd)/monitor.sh") | crontab -
    (crontab -l 2>/dev/null | grep -v "$(pwd)/monitor.sh" ; echo "0 9 * * * cd $(pwd) && /bin/bash $(pwd)/monitor.sh >> $(pwd)/monitor.log 2>&1") | crontab -

    if [ $? -eq 0 ]; then
        echo -e "${GREEN}定时任务设置成功！脚本将每天上午9点自动运行。${NC}"
        echo "日志文件将保存在 $(pwd)/monitor.log"
    else
        echo -e "${RED}设置定时任务失败。请手动设置。${NC}"
        echo "请将以下内容添加到您的 crontab 中:"
        echo "0 9 * * * /bin/bash $(pwd)/monitor.sh"
    fi

    echo ""
    echo -e "${GREEN}🎉 全部设置完成！ 🎉${NC}"
    exit 0
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
            sleep 2
            ;;
    esac
done
