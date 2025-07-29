#!/bin/bash

# ==============================================================================
# GitHub: everett7623/domainmonitor
#
# 功能: 自动监控域名注册状态并通过 Telegram Bot 发送通知
#
# 这个安装脚本会执行以下操作:
# 1. 检查必要的依赖 (Git, Python3, Pip)。
# 2. 从 GitHub 克隆最新的源码。
# 3. 创建一个 Python 虚拟环境以隔离依赖。
# 4. 安装所需的 Python 库。
# 5. 引导用户输入要监控的域名和 Telegram Bot 信息。
# 6. 设置一个 Cron 定时任务来定期执行监控脚本。
# 7. 生成一个管理脚本 `manage.sh` 方便后续操作。
#
# ==============================================================================

# 定义颜色
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[0;33m'
NC='\033[0m' # No Color

# 定义项目信息
GITHUB_USER="everett7623"
GITHUB_REPO="domainmonitor"
INSTALL_DIR="$HOME/domainmonitor"

echo -e "${GREEN}### Domain Monitor 安装程序 ###${NC}"

# --- 步骤 1: 检查依赖 ---
echo -e "\n${YELLOW}[1/7] 正在检查系统依赖...${NC}"
command -v git >/dev/null 2>&1 || { echo -e >&2 "${RED}错误: Git 未安装。请先安装 Git。${NC}"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo -e >&2 "${RED}错误: Python 3 未安装。请先安装 Python 3。${NC}"; exit 1; }
command -v pip3 >/dev/null 2>&1 || { echo -e >&2 "${RED}错误: Pip3 未安装。请先安装 Pip3。${NC}"; exit 1; }
echo -e "${GREEN}依赖检查通过!${NC}"

# --- 步骤 2: 克隆仓库 ---
if [ -d "$INSTALL_DIR" ]; then
    echo -e "\n${YELLOW}检测到已存在的目录 $INSTALL_DIR。是否覆盖? (y/n)${NC}"
    read -r -p "选择: " response
    if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
        rm -rf "$INSTALL_DIR"
    else
        echo -e "${RED}安装已取消。${NC}"
        exit 1
    fi
fi
echo -e "\n${YELLOW}[2/7] 正在从 GitHub 克隆仓库...${NC}"
git clone "https://github.com/${GITHUB_USER}/${GITHUB_REPO}.git" "$INSTALL_DIR" || { echo -e >&2 "${RED}克隆仓库失败!${NC}"; exit 1; }
cd "$INSTALL_DIR" || exit

# --- 步骤 3: 创建 Python 虚拟环境 ---
echo -e "\n${YELLOW}[3/7] 正在创建 Python 虚拟环境...${NC}"
python3 -m venv venv || { echo -e >&2 "${RED}创建虚拟环境失败!${NC}"; exit 1; }

# --- 步骤 4: 安装 Python 依赖 ---
echo -e "\n${YELLOW}[4/7] 正在安装 Python 依赖库 (这可能需要一些时间)...${NC}"
source venv/bin/activate
pip3 install --upgrade pip > /dev/null 2>&1
pip3 install -r requirements.txt || { echo -e >&2 "${RED}安装依赖库失败!${NC}"; exit 1; }
deactivate
echo -e "${GREEN}依赖库安装成功!${NC}"

# --- 步骤 5: 获取用户配置 ---
echo -e "\n${YELLOW}[5/7] 正在配置监控信息...${NC}"
echo "--------------------------------------------------"
echo "请输入你的 Telegram Bot Token。"
echo "如何获取? -> 与 @BotFather 对话, 创建一个新的 Bot。"
read -r -p "Bot Token: " BOT_TOKEN
while [ -z "$BOT_TOKEN" ]; do
    echo -e "${RED}Bot Token 不能为空!${NC}"
    read -r -p "Bot Token: " BOT_TOKEN
done

echo "--------------------------------------------------"
echo "请输入你的 Telegram Chat ID。"
echo "如何获取? -> 与 @userinfobot 对话, 获取你的 'Id'。"
read -r -p "Chat ID: " CHAT_ID
while [ -z "$CHAT_ID" ]; do
    echo -e "${RED}Chat ID 不能为空!${NC}"
    read -r -p "Chat ID: " CHAT_ID
done

echo "--------------------------------------------------"
echo "请输入你想要监控的域名, 多个域名请用空格隔开。"
echo "例如: example.com mydomain.net"
read -r -p "域名列表: " DOMAIN_LIST
while [ -z "$DOMAIN_LIST" ]; do
    echo -e "${RED}域名列表不能为空!${NC}"
    read -r -p "域名列表: " DOMAIN_LIST
done

# 创建配置文件和域名列表文件
touch config.ini
echo "[telegram]" > config.ini
echo "bot_token = $BOT_TOKEN" >> config.ini
echo "chat_id = $CHAT_ID" >> config.ini

touch domains.txt
for domain in $DOMAIN_LIST; do
    echo "$domain" >> domains.txt
done
echo -e "${GREEN}配置信息已保存!${NC}"


# --- 步骤 6: 设置 Cron 定时任务 ---
echo -e "\n${YELLOW}[6/7] 正在设置 Cron 定时任务 (每小时的第15分钟执行一次)...${NC}"
# 获取脚本的绝对路径
PYTHON_EXEC="$INSTALL_DIR/venv/bin/python"
SCRIPT_PATH="$INSTALL_DIR/domain_monitor.py"
LOG_FILE="$INSTALL_DIR/cron.log"

# 删除旧的定时任务
(crontab -l 2>/dev/null | grep -v "$SCRIPT_PATH" ; echo "15 * * * * cd $INSTALL_DIR && $PYTHON_EXEC $SCRIPT_PATH >> $LOG_FILE 2>&1") | crontab -
echo -e "${GREEN}定时任务设置成功!${NC}"


# --- 步骤 7: 生成管理脚本 ---
echo -e "\n${YELLOW}[7/7] 正在生成管理脚本 (manage.sh)...${NC}"
# manage.sh 脚本已在仓库中，这里仅赋予执行权限
chmod +x "$INSTALL_DIR/manage.sh"
echo -e "${GREEN}管理脚本已就绪!${NC}"

# --- 安装完成 ---
echo -e "\n🎉 ${GREEN}恭喜! Domain Monitor 已成功安装!${NC} 🎉"
echo "--------------------------------------------------"
echo "你的所有文件都位于: ${YELLOW}$INSTALL_DIR${NC}"
echo "你可以使用以下命令来管理你的监控列表:"
echo -e "  ${YELLOW}cd $INSTALL_DIR && ./manage.sh${NC}"
echo "监控脚本将自动在每小时的第15分钟运行。"
echo "你可以通过查看日志文件来确认运行状态:"
echo -e "  - 运行日志: ${YELLOW}tail -f $INSTALL_DIR/run.log${NC}"
echo -e "  - 历史状态: ${YELLOW}cat $INSTALL_DIR/history.log${NC}"
echo "--------------------------------------------------"

# 尝试发送一条测试通知
echo -e "\n${YELLOW}正在发送一条测试通知到你的 Telegram...${NC}"
source "$INSTALL_DIR/venv/bin/activate"
python -c "import configparser; import telegram; config = configparser.ConfigParser(); config.read('config.ini'); bot = telegram.Bot(token=config['telegram']['bot_token']); bot.send_message(chat_id=config['telegram']['chat_id'], text='✅ Domain Monitor 安装成功！脚本已开始运行。')"
deactivate
echo -e "${GREEN}测试通知已发送, 请检查你的 Telegram!${NC}"
