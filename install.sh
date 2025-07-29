#!/bin/bash

# 域名监控服务 - 一键安装脚本
# 极简版本，只包含必要组件

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${BLUE}======================================"
echo "    域名监控服务 - 一键安装"
echo "======================================${NC}"

# 检查 root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}请使用 root 用户运行${NC}"
    exit 1
fi

# 安装目录
DIR="/opt/domain-monitor"

echo -e "\n${GREEN}[1/4] 安装系统依赖...${NC}"
apt-get update -qq
apt-get install -y python3 python3-pip python3-venv supervisor >/dev/null 2>&1

echo -e "${GREEN}[2/4] 创建项目环境...${NC}"
mkdir -p $DIR
cd $DIR

# 创建虚拟环境
python3 -m venv venv
source venv/bin/activate

# 安装 Python 包
pip install -q python-whois requests

echo -e "${GREEN}[3/4] 创建程序文件...${NC}"

# 复制脚本文件（从当前目录或下载）
if [ -f "domain_monitor.py" ]; then
    cp domain_monitor.py menu.py $DIR/
else
    # 如果本地没有，从 GitHub 下载
    echo "下载程序文件..."
    curl -sL https://raw.githubusercontent.com/everett7623/domainmonitor/main/domain_monitor.py -o domain_monitor.py
    curl -sL https://raw.githubusercontent.com/everett7623/domainmonitor/main/menu.py -o menu.py
fi

chmod +x menu.py

# 创建 Supervisor 配置
cat > /etc/supervisor/conf.d/domain-monitor.conf << EOF
[program:domain-monitor]
command=$DIR/venv/bin/python $DIR/domain_monitor.py
directory=$DIR
user=root
autostart=true
autorestart=true
redirect_stderr=true
stdout_logfile=/var/log/domain-monitor.log
EOF

supervisorctl reread >/dev/null 2>&1
supervisorctl update >/dev/null 2>&1

echo -e "${GREEN}[4/4] 安装完成！${NC}\n"

echo -e "${YELLOW}启动管理菜单：${NC}"
echo -e "cd $DIR && ./menu.py\n"

# 询问是否立即启动
read -p "是否现在启动管理菜单？(y/n): " start_menu
if [[ "$start_menu" =~ ^[Yy]$ ]]; then
    cd $DIR
    ./menu.py
fi
