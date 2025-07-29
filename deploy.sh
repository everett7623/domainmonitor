#!/bin/bash

# 域名监控服务一键部署脚本
# 支持 Ubuntu/Debian 系统

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}====================================="
echo "域名监控服务一键部署脚本"
echo "=====================================${NC}"

# 检查是否为 root 用户
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用 root 用户运行此脚本${NC}"
    exit 1
fi

# 更新系统
echo -e "${YELLOW}1. 更新系统包...${NC}"
apt-get update
apt-get upgrade -y

# 安装必要的软件
echo -e "${YELLOW}2. 安装 Python 3 和依赖...${NC}"
apt-get install -y python3 python3-pip python3-venv git supervisor

# 创建项目目录
PROJECT_DIR="/opt/domain-monitor"
echo -e "${YELLOW}3. 创建项目目录: $PROJECT_DIR${NC}"
mkdir -p $PROJECT_DIR

# 获取当前脚本所在目录
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 复制项目文件
echo -e "${YELLOW}4. 复制项目文件...${NC}"
cp -r "$SCRIPT_DIR"/* "$PROJECT_DIR/"
cd "$PROJECT_DIR"

# 创建虚拟环境
echo -e "${YELLOW}5. 创建 Python 虚拟环境...${NC}"
python3 -m venv venv
source venv/bin/activate

# 安装 Python 依赖
echo -e "${YELLOW}6. 安装 Python 依赖包...${NC}"
pip install --upgrade pip

# 如果有 requirements.txt 使用它，否则直接安装
if [ -f "requirements.txt" ]; then
    pip install -r requirements.txt
else
    pip install python-whois requests schedule
fi

# 交互式配置 Telegram
echo -e "${YELLOW}7. 配置 Telegram Bot...${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}获取 Bot Token 的步骤：${NC}"
echo "1) 在 Telegram 中搜索 @BotFather"
echo "2) 发送 /newbot 创建新机器人"
echo "3) 按提示设置 bot 名称和用户名"
echo "4) 复制生成的 Token"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 输入 Bot Token
read -p "请输入 Telegram Bot Token: " bot_token
while [ -z "$bot_token" ]; do
    echo -e "${RED}Bot Token 不能为空！${NC}"
    read -p "请输入 Telegram Bot Token: " bot_token
done

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}获取 Chat ID 的步骤：${NC}"
echo "1) 给你刚创建的 Bot 发送任意消息"
echo "2) 在浏览器访问以下地址："
echo "   https://api.telegram.org/bot${bot_token}/getUpdates"
echo "3) 找到 \"chat\":{\"id\":数字} 中的数字"
echo "   或者使用 @userinfobot 获取你的 ID"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 输入 Chat ID
read -p "请输入 Telegram Chat ID: " chat_id
while [ -z "$chat_id" ]; do
    echo -e "${RED}Chat ID 不能为空！${NC}"
    read -p "请输入 Telegram Chat ID: " chat_id
done

# 输入检查间隔
read -p "请输入检查间隔（分钟，默认60）: " check_interval
if [ -z "$check_interval" ]; then
    check_interval=60
fi

# 验证 Telegram 配置
echo -e "${YELLOW}正在验证 Telegram 配置...${NC}"
response=$(curl -s -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
    -d "chat_id=${chat_id}" \
    -d "text=✅ 域名监控服务配置验证成功！即将完成部署..." \
    -d "parse_mode=HTML")

if echo "$response" | grep -q '"ok":true'; then
    echo -e "${GREEN}✅ Telegram 配置验证成功！${NC}"
else
    echo -e "${RED}❌ Telegram 配置验证失败！${NC}"
    echo "错误信息：$response"
    echo "请检查 Token 和 Chat ID 是否正确"
    exit 1
fi

# 创建配置文件
cat > config.env << EOF
# Telegram Bot 配置
TELEGRAM_BOT_TOKEN=$bot_token
TELEGRAM_CHAT_ID=$chat_id

# 检查间隔（分钟）
CHECK_INTERVAL_MINUTES=$check_interval
EOF

# 设置配置文件权限
chmod 600 config.env
echo -e "${GREEN}配置文件已创建并设置权限为 600${NC}"

# 创建域名列表文件
if [ ! -f "domains.json" ]; then
    echo "{}" > domains.json
fi

# 设置文件权限
chmod +x manage.sh 2>/dev/null || true
chmod +x menu.sh 2>/dev/null || true

# 配置 Supervisor
echo -e "${YELLOW}8. 配置 Supervisor...${NC}"
cat > /etc/supervisor/conf.d/domain-monitor.conf << EOF
[program:domain-monitor]
command=$PROJECT_DIR/venv/bin/python $PROJECT_DIR/domain_monitor.py
directory=$PROJECT_DIR
user=root
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/domain-monitor.log
environment=PATH="$PROJECT_DIR/venv/bin",$(cat $PROJECT_DIR/config.env | grep -v '^#' | xargs -I {} echo '{}' | tr '\n' ',')
EOF

# 重新加载 Supervisor 配置
echo -e "${YELLOW}9. 启动服务...${NC}"
supervisorctl reread
supervisorctl update

# 添加第一个域名（可选）
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
read -p "是否现在添加要监控的域名？(y/n): " add_domain
if [[ "$add_domain" =~ ^[Yy]$ ]]; then
    while true; do
        read -p "请输入域名（直接回车结束）: " domain
        if [ -z "$domain" ]; then
            break
        fi
        read -p "添加备注（可选）: " notes
        cd "$PROJECT_DIR"
        ./manage.sh add "$domain" "$notes"
        echo -e "${GREEN}✓ 已添加域名: $domain${NC}"
    done
fi

# 最终启动确认
echo ""
read -p "是否立即启动域名监控服务？(y/n): " start_service
if [[ "$start_service" =~ ^[Yy]$ ]]; then
    supervisorctl start domain-monitor
    echo -e "${GREEN}✓ 域名监控服务已启动${NC}"
else
    echo -e "${YELLOW}你可以稍后使用以下命令启动服务：${NC}"
    echo "sudo supervisorctl start domain-monitor"
fi

echo ""
echo -e "${GREEN}====================================="
echo "部署完成！"
echo "=====================================${NC}"
echo ""
echo -e "${BLUE}使用交互式菜单管理系统：${NC}"
echo ""
echo "  cd $PROJECT_DIR"
echo "  ./menu.sh"
echo ""
echo -e "${YELLOW}快捷命令：${NC}"
echo "  查看服务状态: sudo supervisorctl status domain-monitor"
echo "  查看实时日志: tail -f /var/log/domain-monitor.log"
echo "  添加域名: cd $PROJECT_DIR && ./manage.sh add example.com"
echo ""
echo -e "${GREEN}现在你可以运行 ./menu.sh 开始使用！${NC}"

# 自动进入菜单（可选）
echo ""
read -p "是否现在打开管理菜单？(y/n): " open_menu
if [[ "$open_menu" =~ ^[Yy]$ ]]; then
    cd "$PROJECT_DIR"
    ./menu.sh
fi
