#!/bin/bash

# 域名监控服务安全配置脚本
# 用于初始化或更新敏感配置

set -e

echo "====================================="
echo "域名监控服务 - 安全配置"
echo "====================================="

# 检查是否在正确的目录
if [ ! -f "domain_monitor.py" ]; then
    echo "错误：请在项目目录中运行此脚本"
    exit 1
fi

# 函数：安全输入密码/token
secure_input() {
    local prompt=$1
    local var_name=$2
    local input_value
    
    echo -n "$prompt"
    read -s input_value
    echo
    
    while [ -z "$input_value" ]; do
        echo "输入不能为空！"
        echo -n "$prompt"
        read -s input_value
        echo
    done
    
    eval "$var_name='$input_value'"
}

# 函数：验证 Telegram 配置
verify_telegram_config() {
    local token=$1
    local chat_id=$2
    
    echo "正在验证 Telegram 配置..."
    
    # 测试发送消息
    response=$(curl -s -X POST "https://api.telegram.org/bot${token}/sendMessage" \
        -d "chat_id=${chat_id}" \
        -d "text=✅ 域名监控服务配置验证成功！" \
        -d "parse_mode=HTML")
    
    if echo "$response" | grep -q '"ok":true'; then
        echo "✅ Telegram 配置验证成功！"
        return 0
    else
        echo "❌ Telegram 配置验证失败！"
        echo "错误信息：$response"
        return 1
    fi
}

# 主配置流程
echo ""
echo "1. 配置 Telegram Bot"
echo "------------------------"
echo "获取 Bot Token 的步骤："
echo "  1) 在 Telegram 中搜索 @BotFather"
echo "  2) 发送 /newbot 创建新机器人"
echo "  3) 复制生成的 Token"
echo ""

secure_input "请输入 Telegram Bot Token: " BOT_TOKEN

echo ""
echo "获取 Chat ID 的步骤："
echo "  1) 在 Telegram 中搜索你的 Bot 并发送任意消息"
echo "  2) 访问: https://api.telegram.org/bot${BOT_TOKEN}/getUpdates"
echo "  3) 找到 'chat':{'id': 数字} 中的数字"
echo "  或者使用 @userinfobot 获取你的 ID"
echo ""

read -p "请输入 Telegram Chat ID: " CHAT_ID

# 验证配置
echo ""
if verify_telegram_config "$BOT_TOKEN" "$CHAT_ID"; then
    echo ""
    echo "2. 配置检查间隔"
    echo "------------------------"
    read -p "请输入检查间隔（分钟，默认60，建议30-120）: " CHECK_INTERVAL
    
    if [ -z "$CHECK_INTERVAL" ]; then
        CHECK_INTERVAL=60
    fi
    
    # 创建或更新配置文件
    echo ""
    echo "3. 保存配置"
    echo "------------------------"
    
    # 备份旧配置
    if [ -f "config.env" ]; then
        cp config.env config.env.bak
        echo "已备份旧配置到 config.env.bak"
    fi
    
    # 写入新配置
    cat > config.env << EOF
# Telegram Bot 配置
# 此文件包含敏感信息，请勿提交到版本控制系统
TELEGRAM_BOT_TOKEN=$BOT_TOKEN
TELEGRAM_CHAT_ID=$CHAT_ID

# 检查间隔（分钟）
CHECK_INTERVAL_MINUTES=$CHECK_INTERVAL

# 生成时间：$(date)
EOF
    
    # 设置严格的文件权限
    chmod 600 config.env
    
    echo "✅ 配置已保存并设置权限为 600（仅所有者可读写）"
    
    # 添加到 .gitignore
    if [ -f ".gitignore" ]; then
        if ! grep -q "config.env" .gitignore; then
            echo "config.env" >> .gitignore
            echo "已将 config.env 添加到 .gitignore"
        fi
    else
        echo "config.env" > .gitignore
        echo "*.log" >> .gitignore
        echo "domains.json" >> .gitignore
        echo "已创建 .gitignore 文件"
    fi
    
    echo ""
    echo "====================================="
    echo "配置完成！"
    echo "====================================="
    echo ""
    echo "安全建议："
    echo "1. 定期更换 Bot Token"
    echo "2. 不要在公共场合暴露 Chat ID"
    echo "3. 使用 VPN 或代理访问 Telegram API（如果需要）"
    echo "4. 定期检查日志文件是否有异常"
    echo ""
    echo "下一步："
    echo "- 添加域名：./manage.sh add example.com"
    echo "- 启动服务：sudo supervisorctl start domain-monitor"
    echo ""
else
    echo ""
    echo "配置验证失败，请检查："
    echo "1. Bot Token 是否正确"
    echo "2. Chat ID 是否正确"
    echo "3. 是否已经给 Bot 发送过消息"
    echo "4. 网络连接是否正常"
    exit 1
fi
