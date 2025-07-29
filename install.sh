#!/bin/bash

# 域名监控服务快速安装脚本
# 一键从 GitHub 安装并配置

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

clear
echo -e "${BLUE}╔════════════════════════════════════════╗"
echo -e "║      域名监控服务 - 一键安装脚本       ║"
echo -e "╚════════════════════════════════════════╝${NC}"
echo ""

# 检查是否为 root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}错误：请使用 root 用户运行${NC}"
    echo "使用命令: sudo bash install.sh"
    exit 1
fi

# 检查系统
if ! command -v apt-get &> /dev/null; then
    echo -e "${RED}错误：此脚本仅支持 Debian/Ubuntu 系统${NC}"
    exit 1
fi

echo -e "${GREEN}[1/5] 准备安装环境...${NC}"
apt-get update -qq
apt-get install -y git curl > /dev/null 2>&1

echo -e "${GREEN}[2/5] 下载项目文件...${NC}"
cd /opt
if [ -d "domainmonitor" ]; then
    echo "检测到已存在的安装，是否覆盖？(y/n)"
    read -p "> " overwrite
    if [[ "$overwrite" =~ ^[Yy]$ ]]; then
        rm -rf domainmonitor
    else
        echo "安装已取消"
        exit 0
    fi
fi

git clone https://github.com/everett7623/domainmonitor.git > /dev/null 2>&1
cd domainmonitor

echo -e "${GREEN}[3/5] 执行安装...${NC}"
chmod +x deploy.sh
./deploy.sh

echo ""
echo -e "${GREEN}✅ 安装完成！${NC}"
echo ""
echo -e "${BLUE}立即开始使用：${NC}"
echo "cd /opt/domainmonitor && ./menu.sh"
echo ""
