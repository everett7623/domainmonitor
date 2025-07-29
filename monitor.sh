#!/bin/bash

#----------------------------------------------------------------
# 脚本：monitor.sh
# 功能：监控域名到期时间并通过 Telegram Bot 发送通知
# 作者：Gemini
#----------------------------------------------------------------

# 配置文件路径
CONFIG_FILE="$HOME/.domain_monitor.conf"
TELEGRAM_CONFIG="$HOME/.telegram.conf"
LOG_FILE="/tmp/domain_monitor.log"

# 加载配置
source "$CONFIG_FILE"
source "$TELEGRAM_CONFIG"

# 日志记录
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# 发送 Telegram 消息
send_telegram_message() {
    local message="$1"
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        -d "chat_id=${TELEGRAM_CHAT_ID}" \
        -d "text=${message}" > /dev/null
}

# 检查域名到期时间
check_domain() {
    local domain="$1"
    local expiration_date
    expiration_date=$(whois "$domain" | grep -i "Expiration Date" | awk '{print $NF}')
    
    if [ -z "$expiration_date" ]; then
        log "无法获取域名 '$domain' 的到期日期。"
        return
    fi
    
    local expiration_epoch
    expiration_epoch=$(date -d "$expiration_date" +%s)
    local current_epoch
    current_epoch=$(date +%s)
    
    local days_left
    days_left=$(((expiration_epoch - current_epoch) / 86400))
    
    if [ "$days_left" -lt 30 ]; then
        local message="警告：域名 '$domain' 将在 $days_left 天后到期！"
        log "$message"
        send_telegram_message "$message"
    else
        log "域名 '$domain' 状态正常，剩余 $days_left 天。"
    fi
}

# 主函数
main() {
    log "开始执行域名到期检查..."
    for domain in "${DOMAINS_TO_MONITOR[@]}"; do
        check_domain "$domain"
    done
    log "域名到期检查执行完毕。"
}

main
