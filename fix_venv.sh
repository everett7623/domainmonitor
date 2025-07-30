#!/bin/bash
#
# Domain Monitor 虚拟环境修复脚本
# 用于解决 python3-venv 缺失的问题
#

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}========================================${NC}"
echo -e "${YELLOW}  Domain Monitor 环境修复工具${NC}"
echo -e "${CYAN}========================================${NC}"
echo

# 检测 Python 版本
if command -v python3 >/dev/null 2>&1; then
    PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
    echo -e "${GREEN}✓ 检测到 Python ${PYTHON_VERSION}${NC}"
else
    echo -e "${RED}✗ 未找到 Python3${NC}"
    exit 1
fi

# 检测系统类型
if command -v apt-get >/dev/null 2>&1; then
    echo -e "${BLUE}检测到 Debian/Ubuntu 系统${NC}"
    echo
    echo -e "${YELLOW}即将安装 python${PYTHON_VERSION}-venv 包...${NC}"
    echo -e "${CYAN}需要管理员权限，请输入密码：${NC}"
    
    # 安装 venv 包
    sudo apt-get update
    sudo apt-get install -y python${PYTHON_VERSION}-venv
    
    if [ $? -eq 0 ]; then
        echo
        echo -e "${GREEN}✅ 安装成功！${NC}"
        echo
        echo -e "${CYAN}现在可以重新运行安装脚本了：${NC}"
        echo -e "${GREEN}bash <(curl -sSL https://raw.githubusercontent.com/everett7623/domainmonitor/main/install.sh)${NC}"
    else
        echo -e "${RED}✗ 安装失败，请检查错误信息${NC}"
        exit 1
    fi
    
elif command -v yum >/dev/null 2>&1; then
    echo -e "${BLUE}检测到 RedHat/CentOS 系统${NC}"
    echo -e "${YELLOW}请运行：sudo yum install python3-virtualenv${NC}"
    
elif command -v dnf >/dev/null 2>&1; then
    echo -e "${BLUE}检测到 Fedora 系统${NC}"
    echo -e "${YELLOW}请运行：sudo dnf install python3-virtualenv${NC}"
    
else
    echo -e "${YELLOW}未能识别系统类型，请手动安装虚拟环境支持${NC}"
fi

echo
