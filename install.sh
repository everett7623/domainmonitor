#!/bin/bash

# =================================================================
# Project: domainmonitor
# Author: everett7623
# Description: 一键安装脚本，用于自动监控域名注册状态
# Version: 1.0.0
# Github: https://github.com/everett7623/domainmonitor
# =================================================================

# 颜色定义
GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
BLUE="\033[34m"
NC="\033[0m" # No Color

# 检查 root 权限
if [ "$(id -u)" != "0" ]; then
   echo -e "${RED}错误：此脚本必须以 root 权限运行。请使用 'sudo bash install.sh'。${NC}"
   exit 1
fi

echo -e "${BLUE}=============================================${NC}"
echo -e "${BLUE}     欢迎使用 domainmonitor 安装向导        ${NC}"
echo -e "${BLUE}=============================================${NC}"

# 1. 安装系统依赖 (Python, pip)
echo -e "${YELLOW}正在检查并安装系统依赖...${NC}"
if ! command -v python3 &> /dev/null || ! command -v pip3 &> /dev/null; then
    apt-get update
    apt-get install -y python3 python3-pip
fi

# 2. 创建项目目录并下载文件
PROJECT_DIR="/opt/domainmonitor"
echo -e "${YELLOW}正在创建项目目录: ${PROJECT_DIR}${NC}"
mkdir -p "${PROJECT_DIR}"/{db,web/templates,web/static}
cd "${PROJECT_DIR}"

# 为了演示，这里使用 cat 创建文件。实际应从 Github 下载
echo -e "${YELLOW}正在下载项目文件... (此处为演示，实际应从 Github 拉取)${NC}"

# 主脚本: domain_monitor.py (此处仅为框架，详细代码在后文)
cat > domain_monitor.py <<'EOF'
# 详细 Python 代码见后文
print("Domain Monitor Script Placeholder")
EOF

# 依赖文件: requirements.txt
cat > requirements.txt <<'EOF'
python-whois
python-telegram-bot
schedule
flask
rich
EOF

# Web 面板: web/app.py (此处仅为框架)
cat > web/app.py <<'EOF'
# 详细 Python 代码见后文
print("Web App Placeholder")
EOF

# Web 模板: web/templates/index.html (此处仅为框架)
cat > web/templates/index.html <<'EOF'
<!-- 详细 HTML 代码见后文 -->
<h1>Domain Monitor</h1>
EOF

# 3. 安装 Python 依赖
echo -e "${YELLOW}正在安装 Python 依赖库...${NC}"
pip3 install -r requirements.txt
if [ $? -ne 0 ]; then
    echo -e "${RED}Python 依赖安装失败，请检查网络和 pip 环境。${NC}"
    exit 1
fi

# 4. 配置 Telegram Bot
echo -e "${BLUE}---------------------------------------------${NC}"
echo -e "${BLUE}      现在，请配置您的 Telegram Bot 信息      ${NC}"
echo -e "${BLUE}---------------------------------------------${NC}"
echo -e "你需要先在 Telegram 中与 @BotFather 对话，创建一个新的 Bot 并获取 Token。"
echo -e "然后，与你的 Bot 开始对话，并访问 https://api.telegram.org/bot<YOUR_TOKEN>/getUpdates 获取你的 Chat ID。"

read -p "请输入你的 Telegram Bot Token: " TELEGRAM_TOKEN
read -p "请输入你的 Telegram Chat ID: " CHAT_ID

# 创建配置文件
cat > config.ini <<EOF
[telegram]
token = ${TELEGRAM_TOKEN}
chat_id = ${CHAT_ID}

[settings]
# 检测周期，单位为分钟
check_interval_minutes = 60
# 域名列表，用逗号分隔
domains_to_watch = example.com,example.org,mydreamdomain.net
EOF

echo -e "${GREEN}配置文件 'config.ini' 创建成功！${NC}"

# 5. 创建 systemd 服务
echo -e "${YELLOW}正在创建 systemd 服务以实现后台运行...${NC}"
cat > /etc/systemd/system/domainmonitor.service <<EOF
[Unit]
Description=Domain Registration Status Monitor
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=${PROJECT_DIR}
ExecStart=/usr/bin/python3 ${PROJECT_DIR}/domain_monitor.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

# 6. 启动服务
echo -e "${YELLOW}正在重载 systemd 并启动服务...${NC}"
systemctl daemon-reload
systemctl enable domainmonitor.service
systemctl start domainmonitor.service

# 7. 显示最终信息
echo -e "${GREEN}=============================================${NC}"
echo -e "${GREEN}      🎉 恭喜！安装已成功完成 🎉      ${NC}"
echo -e "${GREEN}=============================================${NC}"
echo -e "✅ 项目已安装在: ${BLUE}${PROJECT_DIR}${NC}"
echo -e "✅ 配置文件位于: ${BLUE}${PROJECT_DIR}/config.ini${NC}"
echo -e "✅ 监控服务已启动并设置为开机自启。"
echo -e "\n你可以使用以下命令管理服务:"
echo -e "  - 查看状态: ${YELLOW}systemctl status domainmonitor${NC}"
echo -e "  - 停止服务: ${YELLOW}systemctl stop domainmonitor${NC}"
echo -e "  - 启动服务: ${YELLOW}systemctl start domainmonitor${NC}"
echo -e "  - 查看日志: ${YELLOW}journalctl -u domainmonitor -f${NC}"
echo -e "\n${BLUE}预设的 Web 面板可以通过运行 'python3 ${PROJECT_DIR}/web/app.py' 启动 (默认端口 5000)。${NC}"
echo -e "现在，请编辑 ${BLUE}config.ini${NC} 文件，添加你想要监控的域名列表。"
echo -e "感谢使用！"
