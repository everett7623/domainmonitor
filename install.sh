#!/bin/bash
# ==============================================================================
# 域名监控系统一键安装脚本
# 项目: https://github.com/everett7623/domainmonitor
# 功能: 自动监控域名注册状态，支持Telegram Bot通知
# 作者: everett7623
# 版本: 1.0.0
# 更新: 2025-01-29
# ==============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# 配置文件路径
INSTALL_DIR="/opt/domainmonitor"
CONFIG_FILE="$INSTALL_DIR/config.json"
LOG_DIR="$INSTALL_DIR/logs"
DOMAINS_FILE="$INSTALL_DIR/domains.txt"
SERVICE_FILE="/etc/systemd/system/domainmonitor.service"

# 打印带颜色的信息
print_info() {
    echo -e "${BLUE}[信息]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[成功]${NC} $1"
}

print_error() {
    echo -e "${RED}[错误]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[警告]${NC} $1"
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        exit 1
    fi
}

# 检查系统
check_system() {
    if [[ -f /etc/redhat-release ]]; then
        release="centos"
    elif cat /etc/issue | grep -Eqi "debian"; then
        release="debian"
    elif cat /etc/issue | grep -Eqi "ubuntu"; then
        release="ubuntu"
    elif cat /etc/issue | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
    elif cat /proc/version | grep -Eqi "debian"; then
        release="debian"
    elif cat /proc/version | grep -Eqi "ubuntu"; then
        release="ubuntu"
    elif cat /proc/version | grep -Eqi "centos|red hat|redhat"; then
        release="centos"
    else
        print_error "不支持的操作系统"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    print_info "正在安装依赖..."
    
    if [[ ${release} == "centos" ]]; then
        yum install -y python3 python3-pip git curl wget
    else
        apt-get update
        apt-get install -y python3 python3-pip git curl wget
    fi
    
    # 安装Python依赖
    pip3 install requests python-whois schedule python-telegram-bot==13.7 --break-system-packages 2>/dev/null || pip3 install requests python-whois schedule python-telegram-bot==13.7
    
    print_success "依赖安装完成"
}

# 创建目录结构
create_directories() {
    print_info "创建目录结构..."
    mkdir -p $INSTALL_DIR
    mkdir -p $LOG_DIR
    cd $INSTALL_DIR
    print_success "目录创建完成"
}

# 下载主程序
download_program() {
    print_info "下载主程序..."
    
    # 下载主监控脚本
    cat > $INSTALL_DIR/domain_monitor.py << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import os
import sys
import time
import schedule
import logging
from datetime import datetime, timedelta

# 尝试导入whois
try:
    import whois
except ImportError:
    print("警告: python-whois未安装，将使用备用方法")
    whois = None

import requests

# 尝试导入telegram
try:
    from telegram import Bot
    from telegram.error import TelegramError
except ImportError:
    print("警告: python-telegram-bot未安装，将使用requests发送通知")
    Bot = None

# 配置日志
LOG_DIR = '/opt/domainmonitor/logs'
if not os.path.exists(LOG_DIR):
    os.makedirs(LOG_DIR)

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(os.path.join(LOG_DIR, 'monitor.log')),
        logging.StreamHandler()
    ]
)

class DomainMonitor:
    def __init__(self):
        self.config_file = '/opt/domainmonitor/config.json'
        self.domains_file = '/opt/domainmonitor/domains.txt'
        self.history_file = '/opt/domainmonitor/history.json'
        self.load_config()
        self.load_history()
        
    def load_config(self):
        """加载配置文件"""
        try:
            with open(self.config_file, 'r') as f:
                self.config = json.load(f)
        except:
            self.config = {
                'telegram': {'bot_token': '', 'chat_id': ''},
                'check_interval': 60
            }
            
    def load_history(self):
        """加载历史记录"""
        try:
            with open(self.history_file, 'r') as f:
                self.history = json.load(f)
        except:
            self.history = {}
            
    def save_history(self):
        """保存历史记录"""
        with open(self.history_file, 'w') as f:
            json.dump(self.history, f, indent=2)
            
    def load_domains(self):
        """加载监控域名列表"""
        domains = []
        if os.path.exists(self.domains_file):
            with open(self.domains_file, 'r') as f:
                domains = [line.strip() for line in f if line.strip()]
        return domains
        
    def send_telegram_notification(self, message):
        """发送Telegram通知"""
        if not self.config['telegram']['bot_token'] or not self.config['telegram']['chat_id']:
            logging.warning("Telegram配置不完整，跳过通知")
            return
            
        bot_token = self.config['telegram']['bot_token']
        chat_id = self.config['telegram']['chat_id']
        
        # 方法1: 使用python-telegram-bot
        if Bot is not None:
            try:
                bot = Bot(token=bot_token)
                bot.send_message(
                    chat_id=chat_id,
                    text=message,
                    parse_mode='HTML'
                )
                logging.info("Telegram通知发送成功 (使用python-telegram-bot)")
                return
            except Exception as e:
                logging.error(f"使用python-telegram-bot发送失败: {e}")
        
        # 方法2: 使用requests
        try:
            url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
            data = {
                'chat_id': chat_id,
                'text': message,
                'parse_mode': 'HTML'
            }
            response = requests.post(url, data=data, timeout=10)
            if response.status_code == 200:
                logging.info("Telegram通知发送成功 (使用requests)")
            else:
                logging.error(f"Telegram API返回错误: {response.text}")
        except Exception as e:
            logging.error(f"发送Telegram通知失败: {e}")
            
    def check_domain_status(self, domain):
        """检查域名状态"""
        # 使用python-whois
        if whois is not None:
            try:
                w = whois.whois(domain)
                
                # 判断域名是否已注册
                if w.domain_name is None:
                    return 'available', None, None
                
                # 获取过期时间
                expiry_date = None
                if isinstance(w.expiration_date, list):
                    expiry_date = w.expiration_date[0]
                else:
                    expiry_date = w.expiration_date
                    
                # 计算剩余天数
                days_until_expiry = None
                if expiry_date:
                    days_until_expiry = (expiry_date - datetime.now()).days
                    
                return 'registered', expiry_date, days_until_expiry
                
            except Exception as e:
                logging.error(f"whois检查域名 {domain} 失败: {e}")
        
        # 备用方法：使用系统whois命令
        try:
            import subprocess
            result = subprocess.run(['whois', domain], capture_output=True, text=True, timeout=30)
            if result.returncode == 0:
                output = result.stdout.lower()
                if any(keyword in output for keyword in ['no found', 'not found', 'no match', 'not registered', 'available']):
                    return 'available', None, None
                else:
                    return 'registered', None, None
            else:
                return 'error', None, None
        except Exception as e:
            logging.error(f"系统whois检查失败: {e}")
            return 'error', None, None
            
    def format_notification(self, domain, status, expiry_date, days_until_expiry):
        """格式化通知消息"""
        message = f"<b>🔔 域名监控通知</b>\n\n"
        message += f"<b>域名:</b> {domain}\n"
        message += f"<b>时间:</b> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
        
        if status == 'available':
            message += f"<b>状态:</b> ✅ 可以注册！\n\n"
            message += f"<b>🎯 立即行动!</b>\n"
            message += f"该域名现在可以注册，建议立即前往以下注册商注册：\n\n"
            message += f"• Namecheap: https://www.namecheap.com\n"
            message += f"• GoDaddy: https://www.godaddy.com\n"
            message += f"• Cloudflare: https://www.cloudflare.com/products/registrar/\n"
            message += f"• Porkbun: https://porkbun.com\n\n"
            message += f"<b>💡 注册建议:</b>\n"
            message += f"• 建议注册5-10年\n"
            message += f"• 开启域名隐私保护\n"
            message += f"• 开启自动续费\n"
            message += f"• 使用可靠的DNS服务商"
        elif status == 'registered':
            message += f"<b>状态:</b> ❌ 已被注册\n"
            if expiry_date:
                message += f"<b>过期时间:</b> {expiry_date.strftime('%Y-%m-%d')}\n"
                if days_until_expiry:
                    if days_until_expiry < 30:
                        message += f"<b>剩余天数:</b> ⚠️ {days_until_expiry} 天 (即将过期!)\n"
                    else:
                        message += f"<b>剩余天数:</b> {days_until_expiry} 天\n"
        else:
            message += f"<b>状态:</b> ⚠️ 检查失败\n"
            
        return message
        
    def check_all_domains(self):
        """检查所有域名"""
        domains = self.load_domains()
        if not domains:
            logging.info("没有需要监控的域名")
            return
            
        logging.info(f"开始检查 {len(domains)} 个域名...")
        
        for domain in domains:
            status, expiry_date, days_until_expiry = self.check_domain_status(domain)
            
            # 检查状态是否发生变化
            last_status = self.history.get(domain, {}).get('status')
            
            # 发送通知的条件
            should_notify = False
            
            if status == 'available' and last_status != 'available':
                # 域名变为可注册状态
                should_notify = True
            elif status == 'registered' and days_until_expiry and days_until_expiry < 30:
                # 域名即将过期
                last_notified = self.history.get(domain, {}).get('last_expiry_notification')
                if not last_notified or (datetime.now() - datetime.fromisoformat(last_notified)).days >= 7:
                    should_notify = True
                    self.history.setdefault(domain, {})['last_expiry_notification'] = datetime.now().isoformat()
                    
            if should_notify:
                message = self.format_notification(domain, status, expiry_date, days_until_expiry)
                self.send_telegram_notification(message)
                
            # 更新历史记录
            self.history[domain] = {
                'status': status,
                'last_check': datetime.now().isoformat(),
                'expiry_date': expiry_date.isoformat() if expiry_date else None
            }
            
        self.save_history()
        logging.info("域名检查完成")
        
    def run(self):
        """运行监控"""
        logging.info("域名监控服务启动")
        
        # 立即执行一次检查
        self.check_all_domains()
        
        # 设置定时任务
        schedule.every(self.config.get('check_interval', 60)).minutes.do(self.check_all_domains)
        
        while True:
            schedule.run_pending()
            time.sleep(1)

if __name__ == '__main__':
    monitor = DomainMonitor()
    monitor.run()
EOF

    chmod +x $INSTALL_DIR/domain_monitor.py
    print_success "主程序下载完成"
}

# 创建管理脚本
create_management_script() {
    print_info "创建管理脚本..."
    
    cat > $INSTALL_DIR/manage.sh << 'EOF'
#!/bin/bash

INSTALL_DIR="/opt/domainmonitor"
CONFIG_FILE="$INSTALL_DIR/config.json"
DOMAINS_FILE="$INSTALL_DIR/domains.txt"
SERVICE_NAME="domainmonitor"

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        域名监控管理系统 v1.0          ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}1.${NC} 添加监控域名"
    echo -e "${GREEN}2.${NC} 删除监控域名"
    echo -e "${GREEN}3.${NC} 配置Telegram Bot通知"
    echo -e "${GREEN}4.${NC} 删除Telegram Bot通知"
    echo -e "${GREEN}5.${NC} 查看监控域名列表"
    echo -e "${GREEN}6.${NC} 查看服务状态"
    echo -e "${GREEN}7.${NC} 重启监控服务"
    echo -e "${GREEN}8.${NC} 查看运行日志"
    echo -e "${GREEN}9.${NC} 卸载监控系统"
    echo -e "${GREEN}0.${NC} 退出"
    echo -e "${BLUE}========================================${NC}"
}

add_domain() {
    echo -e "${BLUE}添加监控域名${NC}"
    read -p "请输入要监控的域名: " domain
    
    if [[ -z "$domain" ]]; then
        echo -e "${RED}域名不能为空${NC}"
        return
    fi
    
    # 检查域名是否已存在
    if grep -q "^$domain$" "$DOMAINS_FILE" 2>/dev/null; then
        echo -e "${YELLOW}域名已在监控列表中${NC}"
    else
        echo "$domain" >> "$DOMAINS_FILE"
        echo -e "${GREEN}域名添加成功: $domain${NC}"
        systemctl restart $SERVICE_NAME
    fi
}

delete_domain() {
    echo -e "${BLUE}删除监控域名${NC}"
    
    if [[ ! -f "$DOMAINS_FILE" ]] || [[ ! -s "$DOMAINS_FILE" ]]; then
        echo -e "${YELLOW}监控列表为空${NC}"
        return
    fi
    
    echo -e "${YELLOW}当前监控的域名:${NC}"
    cat -n "$DOMAINS_FILE"
    
    read -p "请输入要删除的域名编号: " num
    
    if [[ "$num" =~ ^[0-9]+$ ]]; then
        domain=$(sed -n "${num}p" "$DOMAINS_FILE")
        if [[ -n "$domain" ]]; then
            sed -i "${num}d" "$DOMAINS_FILE"
            echo -e "${GREEN}已删除域名: $domain${NC}"
            systemctl restart $SERVICE_NAME
        else
            echo -e "${RED}无效的编号${NC}"
        fi
    else
        echo -e "${RED}请输入有效的数字${NC}"
    fi
}

configure_telegram() {
    echo -e "${BLUE}配置Telegram Bot通知${NC}"
    
    read -p "请输入Bot Token: " bot_token
    read -p "请输入Chat ID: " chat_id
    
    if [[ -z "$bot_token" ]] || [[ -z "$chat_id" ]]; then
        echo -e "${RED}Bot Token和Chat ID不能为空${NC}"
        return
    fi
    
    # 更新配置
    python3 -c "
import json
config = {'telegram': {'bot_token': '$bot_token', 'chat_id': '$chat_id'}, 'check_interval': 60}
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
    
    echo -e "${GREEN}Telegram配置成功${NC}"
    
    # 测试通知
    read -p "是否发送测试通知? (y/n): " test
    if [[ "$test" == "y" ]]; then
        python3 -c "
from telegram import Bot
try:
    bot = Bot(token='$bot_token')
    bot.send_message(chat_id='$chat_id', text='✅ 域名监控系统配置成功！')
    print('\033[0;32m测试通知发送成功\033[0m')
except Exception as e:
    print(f'\033[0;31m测试通知发送失败: {e}\033[0m')
"
    fi
    
    systemctl restart $SERVICE_NAME
}

delete_telegram() {
    echo -e "${BLUE}删除Telegram Bot通知${NC}"
    
    python3 -c "
import json
config = {'telegram': {'bot_token': '', 'chat_id': ''}, 'check_interval': 60}
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
    
    echo -e "${GREEN}Telegram配置已删除${NC}"
    systemctl restart $SERVICE_NAME
}

list_domains() {
    echo -e "${BLUE}监控域名列表${NC}"
    
    if [[ ! -f "$DOMAINS_FILE" ]] || [[ ! -s "$DOMAINS_FILE" ]]; then
        echo -e "${YELLOW}监控列表为空${NC}"
    else
        echo -e "${GREEN}当前监控的域名:${NC}"
        cat -n "$DOMAINS_FILE"
    fi
}

check_status() {
    echo -e "${BLUE}服务状态${NC}"
    systemctl status $SERVICE_NAME
}

restart_service() {
    echo -e "${BLUE}重启监控服务${NC}"
    systemctl restart $SERVICE_NAME
    echo -e "${GREEN}服务重启完成${NC}"
}

view_logs() {
    echo -e "${BLUE}查看运行日志 (按Ctrl+C退出)${NC}"
    tail -f $INSTALL_DIR/logs/monitor.log
}

uninstall() {
    echo -e "${RED}警告: 此操作将删除所有配置和数据！${NC}"
    read -p "确定要卸载吗? (yes/no): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        systemctl stop $SERVICE_NAME
        systemctl disable $SERVICE_NAME
        rm -f /etc/systemd/system/$SERVICE_NAME.service
        rm -rf $INSTALL_DIR
        echo -e "${GREEN}域名监控系统已卸载${NC}"
        exit 0
    else
        echo -e "${YELLOW}取消卸载${NC}"
    fi
}

# 主循环
while true; do
    show_menu
    read -p "请选择操作 [0-9]: " choice
    
    case $choice in
        1) add_domain ;;
        2) delete_domain ;;
        3) configure_telegram ;;
        4) delete_telegram ;;
        5) list_domains ;;
        6) check_status ;;
        7) restart_service ;;
        8) view_logs ;;
        9) uninstall ;;
        0) exit 0 ;;
        *) echo -e "${RED}无效的选择${NC}" ;;
    esac
    
    echo
    read -p "按Enter键继续..."
done
EOF

    chmod +x $INSTALL_DIR/manage.sh
    print_success "管理脚本创建完成"
}

# 创建systemd服务
create_service() {
    print_info "创建系统服务..."
    
    cat > $SERVICE_FILE << EOF
[Unit]
Description=Domain Monitor Service
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=/usr/bin/python3 $INSTALL_DIR/domain_monitor.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

    systemctl daemon-reload
    systemctl enable domainmonitor.service
    print_success "系统服务创建完成"
}

# 初始化配置
initialize_config() {
    print_info "初始化配置..."
    
    # 创建空配置文件
    echo '{"telegram": {"bot_token": "", "chat_id": ""}, "check_interval": 60}' > $CONFIG_FILE
    
    # 创建空域名文件
    touch $DOMAINS_FILE
    
    # 创建空历史文件
    echo '{}' > $INSTALL_DIR/history.json
    
    print_success "配置初始化完成"
}

# 配置向导
configuration_wizard() {
    clear
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        域名监控系统配置向导           ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    # 添加域名
    read -p "请输入要监控的域名 (多个域名用空格分隔): " domains
    if [[ -n "$domains" ]]; then
        for domain in $domains; do
            echo "$domain" >> $DOMAINS_FILE
            print_success "添加域名: $domain"
        done
    fi
    
    # 配置Telegram
    echo
    read -p "是否现在配置Telegram通知? (y/n): " setup_telegram
    if [[ "$setup_telegram" == "y" ]]; then
        echo
        echo -e "${YELLOW}获取Telegram Bot Token和Chat ID的方法:${NC}"
        echo "1. 在Telegram中搜索 @BotFather"
        echo "2. 发送 /newbot 创建新机器人"
        echo "3. 按提示设置机器人名称和用户名"
        echo "4. 获得Bot Token"
        echo "5. 搜索您的机器人并发送任意消息"
        echo "6. 访问 https://api.telegram.org/bot<BOT_TOKEN>/getUpdates"
        echo "7. 在返回的JSON中找到chat.id"
        echo
        
        read -p "请输入Bot Token: " bot_token
        read -p "请输入Chat ID: " chat_id
        
        if [[ -n "$bot_token" ]] && [[ -n "$chat_id" ]]; then
            python3 -c "
import json
config = {'telegram': {'bot_token': '$bot_token', 'chat_id': '$chat_id'}, 'check_interval': 60}
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
            print_success "Telegram配置完成"
            
            # 发送测试通知
            echo
            print_info "发送测试通知..."
            python3 -c "
from telegram import Bot
try:
    bot = Bot(token='$bot_token')
    bot.send_message(chat_id='$chat_id', text='✅ 域名监控系统安装成功！\n\n系统将每60分钟检查一次域名状态。')
    print('\033[0;32m测试通知发送成功\033[0m')
except Exception as e:
    print(f'\033[0;31m测试通知发送失败: {e}\033[0m')
"
        fi
    fi
}

# 启动服务
start_service() {
    print_info "启动监控服务..."
    systemctl start domainmonitor.service
    sleep 2
    
    if systemctl is-active --quiet domainmonitor.service; then
        print_success "服务启动成功"
    else
        print_error "服务启动失败，请检查日志"
        journalctl -u domainmonitor.service -n 20
    fi
}

# 显示安装完成信息
show_completion_info() {
    clear
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}      域名监控系统安装成功！           ${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${BLUE}管理命令:${NC} /opt/domainmonitor/manage.sh"
    echo -e "${BLUE}查看日志:${NC} tail -f /opt/domainmonitor/logs/monitor.log"
    echo -e "${BLUE}服务状态:${NC} systemctl status domainmonitor"
    echo
    echo -e "${YELLOW}功能特点:${NC}"
    echo "• 🔍 自动检测域名注册状态"
    echo "• 📱 Telegram Bot即时通知"
    echo "• 📊 记录检查历史"
    echo "• ⏰ 域名到期提醒"
    echo "• 🛠️ 简单的命令行管理"
    echo "• 📝 详细的运行日志"
    echo
    echo -e "${GREEN}立即运行 ${YELLOW}/opt/domainmonitor/manage.sh${GREEN} 开始管理域名监控${NC}"
}

# 主安装流程
main() {
    check_root
    check_system
    
    print_info "开始安装域名监控系统..."
    
    install_dependencies
    create_directories
    download_program
    create_management_script
    create_service
    initialize_config
    configuration_wizard
    start_service
    show_completion_info
}

# 执行安装
main
