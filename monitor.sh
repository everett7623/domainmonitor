#!/bin/bash

#----------------------------------------------------------------
# 脚本：monitor.sh
# 功能：(由Cron调用) 检查所有监控中的域名，对即将到期的域名发送Telegram警告。
# 作者：Gemini & Everett
#----------------------------------------------------------------

# 主目录和配置文件路径
BASE_DIR="$HOME/domainmonitor"
CONFIG_FILE="$BASE_DIR/domains.conf"
TELEGRAM_CONFIG="$BASE_DIR/telegram.conf"
LOG_FILE="$BASE_DIR/monitor.log"

# 如果配置文件不存在则退出
if [ ! -f "$CONFIG_FILE" ] || [ ! -f "$TELEGRAM_CONFIG" ]; then
    echo "配置文件丢失，退出脚本。" >> "$LOG_FILE"
    exit 1
fi

# 加载配置
source "$CONFIG_FILE"
source "$TELEGRAM_CONFIG"

# 日志记录函数
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 发送Telegram消息函数
# 参数1: 消息内容
send_telegram_message() {
    local message="$1"
    # 使用-s静默模式，--max-time设置超时防止脚本卡死
    curl -s --max-time 10 -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" \
        -d "parse_mode=Markdown" > /dev/null
}

# 获取域名详细信息并检查
# 参数1: 域名
check_domain() {
    local domain="$1"
    log "正在检查域名: $domain"
    
    # 使用更兼容的whois查询，并处理可能的多行返回
    local whois_info
    whois_info=$(whois "$domain")
    
    # 兼容多种标签获取过期日期
    local expiration_date
    expiration_date=$(echo "$whois_info" | grep -i -E 'Registry Expiry Date:|Expiration Date:|expires:|Expiry Date:' | head -1 | awk -F': ' '{print $2}')
    
    if [ -z "$expiration_date" ]; then
        log "无法获取域名 '$domain' 的到期日期。"
        send_telegram_message "⚠️ *域名检查失败* ⚠️\n\n无法获取域名 \`$domain\` 的到期日期，请检查域名是否正确或稍后再试。"
        return
    fi
    
    # 转换为时间戳进行计算
    local expiration_epoch
    expiration_epoch=$(date -d "$expiration_date" +%s)
    local current_epoch
    current_epoch=$(date +%s)
    
    local days_left
    days_left=$(((expiration_epoch - current_epoch) / 86400))
    
    # 设置警告阈值 (例如 30, 15, 7 天)
    if [ "$days_left" -lt 30 ]; then
        # 获取创建日期
        local creation_date
        creation_date=$(echo "$whois_info" | grep -i -E 'Creation Date:|Registered on:|Registration Time:' | head -1 | awk -F': ' '{print $2}')
        
        # 格式化消息
        local message
        message=$(cat <<EOF
🔔 *域名到期提醒* 🔔

域名: \`$domain\` 即将到期！

*剩余时间*: $days_left 天
*到期日期*: \`$expiration_date\`
*创建日期*: \`$creation_date\`

请及时续费！
EOF
)
        log "警告: 域名 '$domain' 将在 $days_left 天后到期。"
        send_telegram_message "$message"
    else
        log "域名 '$domain' 状态正常，剩余 $days_left 天。"
        # 你也可以在这里发送一个“一切正常”的通知，但这可能会很吵，所以默认注释掉
        # send_telegram_message "✅ 域名 \`$domain\` 状态正常，剩余 $days_left 天。"
    fi
}

# --- 主程序 ---
log "====== 开始执行每日域名到期检查 ======"

# 检查 DOMAINS_TO_MONITOR 数组是否为空
if [ ${#DOMAINS_TO_MONITOR[@]} -eq 0 ]; then
    log "没有配置任何域名，跳过检查。"
else
    for domain in "${DOMAINS_TO_MONITOR[@]}"; do
        check_domain "$domain"
    done
fi

log "====== 域名检查执行完毕 ======"
