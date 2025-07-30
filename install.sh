#!/bin/bash
# ==============================================================================
# 域名监控系统一键安装脚本
# 项目: https://github.com/everett7623/domainmonitor
# 功能: 自动监控域名注册状态，支持Telegram Bot通知
# 作者: everett7623
# 版本: 2.0.0
# 更新: 2025-07-30
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
GITHUB_RAW="https://raw.githubusercontent.com/everett7623/domainmonitor/main"

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

# 显示Logo
show_logo() {
    clear
    echo -e "${PURPLE}"
    cat << 'EOF'
    ____                        _       __  __             _ __            
   / __ \____  ____ ___  ____ _(_)___  /  |/  /____  ____  (_) /_____  _____
  / / / / __ \/ __ `__ \/ __ `/ / __ \/ /|_/ / __ \/ __ \/ / __/ __ \/ ___/
 / /_/ / /_/ / / / / / / /_/ / / / / / /  / / /_/ / / / / / /_/ /_/ / /    
/_____/\____/_/ /_/ /_/\__,_/_/_/ /_/_/  /_/\____/_/ /_/_/\__/\____/_/     
                                                                            
EOF
    echo -e "${NC}"
    echo -e "${CYAN}域名监控系统 v2.0 - 让心仪域名不再错过${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
}

# 检查root权限
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "此脚本需要root权限运行"
        echo -e "${YELLOW}请使用: sudo bash $0${NC}"
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
    
    print_info "检测到系统: $release"
}

# 安装依赖
install_dependencies() {
    print_info "正在安装系统依赖..."
    
    if [[ ${release} == "centos" ]]; then
        yum install -y epel-release
        yum install -y python3 python3-pip git curl wget whois
    else
        apt-get update
        apt-get install -y python3 python3-pip git curl wget whois
    fi
    
    # 安装Python依赖
    print_info "正在安装Python依赖..."
    pip3 install requests schedule python-telegram-bot==20.7 --break-system-packages 2>/dev/null || \
    pip3 install requests schedule python-telegram-bot==20.7
    
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
    
    # 从GitHub下载主监控脚本
    curl -sL "$GITHUB_RAW/domain_monitor.py" -o $INSTALL_DIR/domain_monitor.py
    
    if [ ! -f "$INSTALL_DIR/domain_monitor.py" ]; then
        print_warning "从GitHub下载失败，使用内置版本"
        create_builtin_monitor
    fi
    
    chmod +x $INSTALL_DIR/domain_monitor.py
    print_success "主程序下载完成"
}

# 创建内置监控程序
create_builtin_monitor() {
    cat > $INSTALL_DIR/domain_monitor.py << 'EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
域名监控系统主程序
支持自动检测域名注册状态并通过Telegram Bot发送通知
"""

import json
import os
import sys
import time
import schedule
import logging
import subprocess
from datetime import datetime, timedelta
from typing import Dict, List, Tuple, Optional

# Telegram通知支持
try:
    import telegram
    from telegram import Bot
    from telegram.error import TelegramError
    TELEGRAM_AVAILABLE = True
except ImportError:
    TELEGRAM_AVAILABLE = False
    print("警告: telegram模块未安装，将使用requests发送通知")

import requests

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/opt/domainmonitor/logs/monitor.log'),
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
            with open(self.config_file, 'r', encoding='utf-8') as f:
                self.config = json.load(f)
        except Exception as e:
            logging.error(f"加载配置文件失败: {e}")
            self.config = {
                'telegram': {'bot_token': '', 'chat_id': ''},
                'check_interval': 60,
                'notify_days_before_expiry':
            }
            
    def load_history(self):
        """加载历史记录"""
        try:
            with open(self.history_file, 'r', encoding='utf-8') as f:
                self.history = json.load(f)
        except:
            self.history = {}
            
    def save_history(self):
        """保存历史记录"""
        try:
            with open(self.history_file, 'w', encoding='utf-8') as f:
                json.dump(self.history, f, indent=2, ensure_ascii=False)
        except Exception as e:
            logging.error(f"保存历史记录失败: {e}")
            
    def load_domains(self) -> List[str]:
        """加载监控域名列表"""
        domains = []
        if os.path.exists(self.domains_file):
            try:
                with open(self.domains_file, 'r', encoding='utf-8') as f:
                    domains = [line.strip().lower() for line in f if line.strip()]
                # 去重
                domains = list(set(domains))
            except Exception as e:
                logging.error(f"加载域名列表失败: {e}")
        return domains
        
    def send_telegram_notification(self, message: str) -> bool:
        """发送Telegram通知"""
        bot_token = self.config.get('telegram', {}).get('bot_token', '')
        chat_id = self.config.get('telegram', {}).get('chat_id', '')
        
        if not bot_token or not chat_id:
            logging.warning("Telegram配置不完整，跳过通知")
            return False
            
        # 方法1: 使用python-telegram-bot库
        if TELEGRAM_AVAILABLE:
            try:
                bot = Bot(token=bot_token)
                bot.send_message(
                    chat_id=chat_id,
                    text=message,
                    parse_mode='HTML',
                    disable_web_page_preview=True
                )
                logging.info("Telegram通知发送成功 (使用python-telegram-bot)")
                return True
            except Exception as e:
                logging.error(f"python-telegram-bot发送失败: {e}")
                
        # 方法2: 使用requests直接调用API
        try:
            url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
            data = {
                'chat_id': chat_id,
                'text': message,
                'parse_mode': 'HTML',
                'disable_web_page_preview': True
            }
            
            response = requests.post(url, data=data, timeout=10)
            if response.status_code == 200:
                logging.info("Telegram通知发送成功 (使用requests)")
                return True
            else:
                logging.error(f"Telegram API返回错误: {response.text}")
                
        except Exception as e:
            logging.error(f"requests发送失败: {e}")
            
        return False
        
    def check_domain_whois(self, domain: str) -> Tuple[str, Optional[datetime], Optional[int]]:
        """使用whois命令检查域名状态"""
        try:
            result = subprocess.run(
                ['whois', domain],
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode != 0:
                return 'error', None, None
                
            output = result.stdout.lower()
            
            # 检查是否未注册
            not_found_keywords = [
                'no found', 'not found', 'no match', 'not registered',
                'available', 'free', 'no data found', 'domain not found',
                'no entries found', 'status: free', 'not exist'
            ]
            
            for keyword in not_found_keywords:
                if keyword in output:
                    return 'available', None, None
                    
            # 尝试解析过期时间
            expiry_date = self.parse_expiry_date(result.stdout)
            
            # 计算剩余天数
            days_until_expiry = None
            if expiry_date:
                days_until_expiry = (expiry_date - datetime.now()).days
                
            return 'registered', expiry_date, days_until_expiry
            
        except subprocess.TimeoutExpired:
            logging.error(f"whois命令超时: {domain}")
            return 'error', None, None
        except Exception as e:
            logging.error(f"whois检查失败: {e}")
            return 'error', None, None
            
    def parse_expiry_date(self, whois_text: str) -> Optional[datetime]:
        """解析whois输出中的过期日期"""
        expiry_keywords = [
            'expiry date:', 'expires on:', 'expiration date:',
            'expire:', 'exp date:', 'expires:', 'expiry:',
            'registry expiry date:', 'registrar registration expiration date:'
        ]
        
        lines = whois_text.split('\n')
        for line in lines:
            line_lower = line.lower()
            for keyword in expiry_keywords:
                if keyword in line_lower:
                    date_str = line.split(':', 1).strip()
                    # 尝试多种日期格式
                    for fmt in [
                        '%Y-%m-%d', '%d-%m-%Y', '%Y/%m/%d', '%d/%m/%Y',
                        '%Y.%m.%d', '%d.%m.%Y', '%Y-%m-%dT%H:%M:%SZ',
                        '%Y-%m-%dT%H:%M:%S%z'
                    ]:
                        try:
                            return datetime.strptime(date_str.split(), fmt)
                        except:
                            continue
        return None
        
    def format_notification(self, domain: str, status: str, expiry_date: Optional[datetime], 
                          days_until_expiry: Optional[int]) -> str:
        """格式化通知消息"""
        message = f"<b>🔔 域名监控通知</b>\n\n"
        message += f"<b>域名:</b> <code>{domain}</code>\n"
        message += f"<b>时间:</b> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n"
        
        if status == 'available':
            message += f"<b>状态:</b> ✅ <b>可以注册！</b>\n\n"
            message += f"<b>🎯 立即行动!</b>\n"
            message += f"该域名现在可以注册，建议立即前往以下注册商注册：\n\n"
            message += f"<b>推荐注册商:</b>\n"
            message += f"• <a href='https://www.namecheap.com/domains/registration/results/?domain={domain}'>Namecheap</a> - 价格实惠\n"
            message += f"• <a href='https://www.godaddy.com/domainsearch/find?domainToCheck={domain}'>GoDaddy</a> - 全球最大\n"
            message += f"• <a href='https://www.cloudflare.com/products/registrar/'>Cloudflare</a> - 成本价\n"
            message += f"• <a href='https://porkbun.com/checkout/search?q={domain}'>Porkbun</a> - 性价比高\n\n"
            message += f"<b>💡 注册建议:</b>\n"
            message += f"• 建议注册5-10年获得优惠\n"
            message += f"• 开启域名隐私保护(WHOIS Privacy)\n"
            message += f"• 开启自动续费避免过期\n"
            message += f"• 使用Cloudflare等可靠DNS\n"
            message += f"• 立即设置域名锁防止转移\n\n"
            message += f"⚡ <b>请尽快行动，好域名稍纵即逝！</b>"
            
        elif status == 'registered':
            message += f"<b>状态:</b> ❌ 已被注册\n"
            if expiry_date:
                message += f"<b>过期时间:</b> {expiry_date.strftime('%Y-%m-%d')}\n"
                if days_until_expiry is not None:
                    if days_until_expiry < 0:
                        message += f"<b>状态:</b> 💀 已过期 {abs(days_until_expiry)} 天\n"
                        message += f"\n⚠️ <b>域名已过期，可能即将释放！</b>"
                    elif days_until_expiry == 0:
                        message += f"<b>状态:</b> 🔥 <b>今天过期！</b>\n"
                        message += f"\n⚠️ <b>密切关注，可能随时释放！</b>"
                    elif days_until_expiry < 7:
                        message += f"<b>剩余天数:</b> 🔥 仅剩 {days_until_expiry} 天！\n"
                        message += f"\n⚠️ <b>即将过期，请密切关注！</b>"
                    elif days_until_expiry < 30:
                        message += f"<b>剩余天数:</b> ⚠️ {days_until_expiry} 天\n"
                        message += f"\n💡 域名即将过期，持续监控中..."
                    else:
                        message += f"<b>剩余天数:</b> {days_until_expiry} 天\n"
            else:
                message += f"\n💡 无法获取过期时间，将持续监控..."
                
        else:
            message += f"<b>状态:</b> ⚠️ 检查失败\n"
            message += f"\n系统将在下次检查时重试..."
            
        return message
        
    def should_notify(self, domain: str, status: str, days_until_expiry: Optional[int]) -> Tuple[bool, str]:
        """判断是否需要发送通知"""
        domain_history = self.history.get(domain, {})
        last_status = domain_history.get('status')
        last_notified = domain_history.get('last_notified')
        
        # 域名变为可注册
        if status == 'available' and last_status != 'available':
            return True, "域名变为可注册"
            
        # 域名可注册且24小时未通知
        if status == 'available' and last_notified:
            last_notified_time = datetime.fromisoformat(last_notified)
            if (datetime.now() - last_notified_time).total_seconds() > 86400:
                return True, "定期提醒(24小时)"
                
        # 域名已过期
        if status == 'registered' and days_until_expiry is not None and days_until_expiry < 0:
            if last_status != 'expired':
                return True, "域名已过期"
                
        # 即将过期提醒
        if status == 'registered' and days_until_expiry is not None:
            notify_days = self.config.get('notify_days_before_expiry',)
            for days in notify_days:
                if days_until_expiry == days:
                    last_notify_key = f'notified_{days}d'
                    if not domain_history.get(last_notify_key):
                        return True, f"域名{days}天后过期"
                        
        return False, ""
        
    def check_all_domains(self):
        """检查所有域名"""
        domains = self.load_domains()
        if not domains:
            logging.info("没有需要监控的域名")
            return
            
        logging.info(f"开始检查 {len(domains)} 个域名...")
        
        checked = 0
        available = 0
        expiring = 0
        
        for domain in domains:
            logging.info(f"正在检查域名: {domain}")
            
            try:
                status, expiry_date, days_until_expiry = self.check_domain_whois(domain)
                
                if status == 'available':
                    available += 1
                elif days_until_expiry is not None and days_until_expiry < 30:
                    expiring += 1
                    
                checked += 1
                
                # 判断是否需要通知
                should_notify, reason = self.should_notify(domain, status, days_until_expiry)
                
                if should_notify:
                    message = self.format_notification(domain, status, expiry_date, days_until_expiry)
                    if self.send_telegram_notification(message):
                        logging.info(f"已发送通知 - {domain}: {reason}")
                        self.history.setdefault(domain, {})['last_notified'] = datetime.now().isoformat()
                        
                        # 记录特定天数的通知
                        if days_until_expiry is not None:
                            for days in self.config.get('notify_days_before_expiry',):
                                if days_until_expiry == days:
                                    self.history[domain][f'notified_{days}d'] = True
                    else:
                        logging.error(f"通知发送失败 - {domain}")
                        
                # 更新历史记录
                self.history.setdefault(domain, {}).update({
                    'status': 'expired' if days_until_expiry and days_until_expiry < 0 else status,
                    'last_check': datetime.now().isoformat(),
                    'expiry_date': expiry_date.isoformat() if expiry_date else None,
                    'days_until_expiry': days_until_expiry
                })
                
                # 清理过期的通知标记
                if status == 'available' or (days_until_expiry and days_until_expiry > 30):
                    for days in:
                        self.history[domain].pop(f'notified_{days}d', None)
                
            except Exception as e:
                logging.error(f"检查域名 {domain} 时发生错误: {e}")
                
            # 避免请求过快
            time.sleep(2)
            
        self.save_history()
        
        # 发送检查摘要
        summary = (
            f"<b>📊 域名检查完成</b>\n\n"
            f"检查域名: {checked} 个\n"
            f"可注册: {available} 个\n"
            f"即将过期: {expiring} 个\n"
            f"时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        )
        
        if available > 0 or expiring > 0:
            self.send_telegram_notification(summary)
            
        logging.info(f"域名检查完成 - 检查: {checked}, 可注册: {available}, 即将过期: {expiring}")
        
    def test_notification(self):
        """测试通知功能"""
        test_message = (
            "<b>🔔 域名监控系统测试</b>\n\n"
            "✅ Telegram通知配置成功！\n"
            f"🕐 当前时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
            f"⏰ 检查间隔: {self.config.get('check_interval', 60)} 分钟\n"
            f"📋 监控域名: {len(self.load_domains())} 个\n\n"
            "系统正在正常运行..."
        )
        
        if self.send_telegram_notification(test_message):
            logging.info("测试通知发送成功")
            return True
        else:
            logging.error("测试通知发送失败")
            return False
            
    def run(self):
        """运行监控"""
        logging.info("域名监控服务启动")
        logging.info(f"检查间隔: {self.config.get('check_interval', 60)} 分钟")
        
        # 测试通知
        if self.config.get('telegram', {}).get('bot_token'):
            self.test_notification()
            
        # 立即执行一次检查
        self.check_all_domains()
        
        # 设置定时任务
        interval = self.config.get('check_interval', 60)
        schedule.every(interval).minutes.do(self.check_all_domains)
        
        logging.info(f"定时任务已设置，每 {interval} 分钟检查一次")
        
        # 主循环
        while True:
            try:
                schedule.run_pending()
                time.sleep(1)
            except KeyboardInterrupt:
                logging.info("收到中断信号，正在退出...")
                break
            except Exception as e:
                logging.error(f"运行时错误: {e}")
                time.sleep(10)

if __name__ == '__main__':
    monitor = DomainMonitor()
    monitor.run()
EOF
}

# 创建管理脚本
create_management_script() {
    print_info "创建管理脚本..."
    
    curl -sL "$GITHUB_RAW/manage.sh" -o $INSTALL_DIR/manage.sh
    
    if [ ! -f "$INSTALL_DIR/manage.sh" ]; then
        print_warning "从GitHub下载失败，使用内置版本"
        create_builtin_manage
    fi
    
    chmod +x $INSTALL_DIR/manage.sh
    print_success "管理脚本创建完成"
}

# 创建内置管理脚本
create_builtin_manage() {
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
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

show_menu() {
    clear
    echo -e "${PURPLE}"
    echo "  ____                  __  __             _ __            "
    echo " |  _ \  ___  _ __ ___ |  \/  | ___  _ __ (_) |_ ___  _ __"
    echo " | | | |/ _ \| '_ \` _ \| |\/| |/ _ \| '_ \| | __/ _ \| '__|"
    echo " | |_| | (_) | | | | | | |  | | (_) | | | | | || (_) | |   "
    echo " |____/ \___/|_| |_| |_|_|  |_|\___/|_| |_|_|\__\___/|_|   "
    echo -e "${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        域名监控管理系统 v2.0          ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo -e "${GREEN}1.${NC} 添加监控域名"
    echo -e "${GREEN}2.${NC} 删除监控域名"
    echo -e "${GREEN}3.${NC} 配置Telegram Bot通知"
    echo -e "${GREEN}4.${NC} 删除Telegram Bot通知"
    echo -e "${GREEN}5.${NC} 查看监控域名列表"
    echo -e "${GREEN}6.${NC} 查看服务状态"
    echo -e "${GREEN}7.${NC} 重启监控服务"
    echo -e "${GREEN}8.${NC} 查看运行日志"
    echo -e "${GREEN}9.${NC} 立即检查所有域名"
    echo -e "${GREEN}10.${NC} 修改检查间隔"
    echo -e "${GREEN}11.${NC} 查看检查历史"
    echo -e "${GREEN}12.${NC} 高级设置"
    echo -e "${GREEN}13.${NC} 卸载监控系统"
    echo -e "${GREEN}0.${NC} 退出"
    echo -e "${BLUE}========================================${NC}"
}

# 验证域名格式
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

add_domain() {
    echo -e "${BLUE}添加监控域名${NC}"
    echo -e "${CYAN}提示: 可以一次输入多个域名，用空格分隔${NC}"
    read -p "请输入要监控的域名: " domains
    
    if [[ -z "$domains" ]]; then
        echo -e "${RED}域名不能为空${NC}"
        return
    fi
    
    added_count=0
    duplicate_count=0
    invalid_count=0
    
    for domain in $domains; do
        # 转换为小写
        domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
        
        # 验证域名格式
        if ! validate_domain "$domain"; then
            echo -e "${RED}✗ 无效的域名格式: $domain${NC}"
            ((invalid_count++))
            continue
        fi
        
        # 检查域名是否已存在
        if grep -q "^$domain$" "$DOMAINS_FILE" 2>/dev/null; then
            echo -e "${YELLOW}! 域名已存在: $domain${NC}"
            ((duplicate_count++))
        else
            echo "$domain" >> "$DOMAINS_FILE"
            echo -e "${GREEN}✓ 添加成功: $domain${NC}"
            ((added_count++))
        fi
    done
    
    echo
    echo -e "${CYAN}统计: 添加 $added_count 个, 重复 $duplicate_count 个, 无效 $invalid_count 个${NC}"
    
    if [ $added_count -gt 0 ]; then
        systemctl restart $SERVICE_NAME
        echo -e "${GREEN}服务已重启，新域名将被监控${NC}"
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
    echo
    echo -e "${CYAN}输入域名编号删除单个，输入 'all' 清空所有域名${NC}"
    read -p "请输入选择: " choice
    
    if [[ "$choice" == "all" ]]; then
        read -p "确定要清空所有域名吗? (yes/no): " confirm
        if [[ "$confirm" == "yes" ]]; then
            > "$DOMAINS_FILE"
            echo -e "${GREEN}已清空所有域名${NC}"
            systemctl restart $SERVICE_NAME
        fi
    elif [[ "$choice" =~ ^[0-9]+$ ]]; then
        domain=$(sed -n "${choice}p" "$DOMAINS_FILE")
        if [[ -n "$domain" ]]; then
            sed -i "${choice}d" "$DOMAINS_FILE"
            echo -e "${GREEN}已删除域名: $domain${NC}"
            systemctl restart $SERVICE_NAME
        else
            echo -e "${RED}无效的编号${NC}"
        fi
    else
        echo -e "${RED}无效的输入${NC}"
    fi
}

configure_telegram() {
    echo -e "${BLUE}配置Telegram Bot通知${NC}"
    echo
    echo -e "${YELLOW}获取Bot Token和Chat ID的步骤:${NC}"
    echo "1. 在Telegram搜索 @BotFather"
    echo "2. 发送 /newbot 创建机器人"
    echo "3. 按提示设置机器人名称和用户名"
    echo "4. 复制Bot Token"
    echo "5. 搜索并打开您的机器人，发送任意消息"
    echo "6. 访问: https://api.telegram.org/bot<TOKEN>/getUpdates"
    echo "7. 找到 \"chat\":{\"id\":数字} 中的数字即为Chat ID"
    echo
    
    # 显示当前配置
    current_token=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c.get('telegram',{}).get('bot_token',''))" 2>/dev/null)
    current_chat=$(python3 -c "import json; c=json.load(open('$CONFIG_FILE')); print(c.get('telegram',{}).get('chat_id',''))" 2>/dev/null)
    
    if [[ -n "$current_token" ]]; then
        echo -e "${CYAN}当前Bot Token: ${current_token:0:10}...${current_token: -4}${NC}"
    fi
    if [[ -n "$current_chat" ]]; then
        echo -e "${CYAN}当前Chat ID: $current_chat${NC}"
    fi
    echo
    
    read -p "请输入Bot Token (回车保持当前): " bot_token
    read -p "请输入Chat ID (回车保持当前): " chat_id
    
    # 如果为空则保持当前值
    bot_token=${bot_token:-$current_token}
    chat_id=${chat_id:-$current_chat}
    
    if [[ -z "$bot_token" ]] || [[ -z "$chat_id" ]]; then
        echo -e "${RED}Bot Token和Chat ID不能为空${NC}"
        return
    fi
    
    # 验证Bot Token
    echo -e "\n${YELLOW}验证Bot Token...${NC}"
    response=$(curl -s "https://api.telegram.org/bot$bot_token/getMe")
    if echo "$response" | grep -q '"ok":true'; then
        bot_name=$(echo "$response" | python3 -c "import json,sys; print(json.load(sys.stdin)['result']['username'])" 2>/dev/null)
        echo -e "${GREEN}✓ Bot验证成功: @$bot_name${NC}"
    else
        echo -e "${RED}✗ Bot Token无效${NC}"
        return
    fi
    
    # 更新配置
    python3 -c "
import json
try:
    with open('$CONFIG_FILE', 'r') as f:
        config = json.load(f)
except:
    config = {}
    
config['telegram'] = {'bot_token': '$bot_token', 'chat_id': '$chat_id'}
if 'check_interval' not in config:
    config['check_interval'] = 60
if 'notify_days_before_expiry' not in config:
    config['notify_days_before_expiry'] = [30, 7, 3, 1]
    
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
    
    echo -e "${GREEN}Telegram配置成功${NC}"
    
    # 测试通知
    read -p "是否发送测试通知? (y/n): " test
    if [[ "$test" == "y" ]]; then
        curl -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" \
             -d "chat_id=$chat_id" \
             -d "text=✅ 域名监控系统配置成功！" \
             -d "parse_mode=HTML" > /dev/null
        echo -e "${GREEN}测试通知已发送${NC}"
    fi
    
    systemctl restart $SERVICE_NAME
}

delete_telegram() {
    echo -e "${BLUE}删除Telegram Bot通知${NC}"
    read -p "确定要删除Telegram配置吗? (yes/no): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
config['telegram'] = {'bot_token': '', 'chat_id': ''}
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
        echo -e "${GREEN}Telegram配置已删除${NC}"
        systemctl restart $SERVICE_NAME
    fi
}

list_domains() {
    echo -e "${BLUE}监控域名列表${NC}"
    
    if [[ ! -f "$DOMAINS_FILE" ]] || [[ ! -s "$DOMAINS_FILE" ]]; then
        echo -e "${YELLOW}监控列表为空${NC}"
    else
        total=$(wc -l < "$DOMAINS_FILE")
        echo -e "${GREEN}共监控 $total 个域名:${NC}"
        echo -e "${BLUE}----------------------------${NC}"
        cat -n "$DOMAINS_FILE"
        echo -e "${BLUE}----------------------------${NC}"
        
        # 显示最近检查状态
        if [[ -f "$INSTALL_DIR/history.json" ]]; then
            echo -e "\n${CYAN}最近检查状态:${NC}"
            python3 << EOF
import json
from datetime import datetime

try:
    with open('$INSTALL_DIR/history.json', 'r') as f:
        history = json.load(f)
    
    for domain, info in history.items():
        status = info.get('status', 'unknown')
        last_check = info.get('last_check', '')
        days_until_expiry = info.get('days_until_expiry')
        
        # 状态图标
        if status == 'available':
            status_icon = '✅'
            status_text = '可注册'
        elif status == 'registered':
            status_icon = '❌'
            status_text = '已注册'
        elif status == 'expired':
            status_icon = '💀'
            status_text = '已过期'
        else:
            status_icon = '⚠️'
            status_text = '未知'
        
        # 时间格式化
        if last_check:
            try:
                check_time = datetime.fromisoformat(last_check)
                time_str = check_time.strftime('%Y-%m-%d %H:%M')
            except:
                time_str = last_check
        else:
            time_str = '从未检查'
        
        # 过期信息
        expiry_info = ''
        if days_until_expiry is not None:
            if days_until_expiry < 0:
                expiry_info = f' (已过期{abs(days_until_expiry)}天)'
            elif days_until_expiry == 0:
                expiry_info = ' (今天过期!)'
            elif days_until_expiry < 30:
                expiry_info = f' (剩余{days_until_expiry}天)'
            
        print(f"{status_icon} {domain} - {status_text}{expiry_info} - {time_str}")
except:
    print("暂无历史记录")
EOF
        fi
    fi
}

check_status() {
    echo -e "${BLUE}服务状态${NC}"
    systemctl status $SERVICE_NAME --no-pager
    
    echo -e "\n${CYAN}检查配置:${NC}"
    interval=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('check_interval', 60))" 2>/dev/null)
    echo "检查间隔: $interval 分钟"
    
    # 显示下次检查时间
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "\n${CYAN}最近日志:${NC}"
        tail -n 5 $INSTALL_DIR/logs/monitor.log 2>/dev/null || echo "暂无日志"
    fi
}

restart_service() {
    echo -e "${BLUE}重启监控服务${NC}"
    systemctl restart $SERVICE_NAME
    sleep 2
    if systemctl is-active --quiet $SERVICE_NAME; then
        echo -e "${GREEN}✓ 服务重启成功${NC}"
    else
        echo -e "${RED}✗ 服务重启失败${NC}"
        echo -e "${YELLOW}查看错误信息:${NC}"
        journalctl -u $SERVICE_NAME -n 10 --no-pager
    fi
}

view_logs() {
    echo -e "${BLUE}查看运行日志 (按Ctrl+C退出)${NC}"
    echo -e "${CYAN}显示最近50行日志...${NC}"
    echo
    tail -n 50 -f $INSTALL_DIR/logs/monitor.log
}

check_now() {
    echo -e "${BLUE}立即检查所有域名${NC}"
    echo -e "${YELLOW}正在触发立即检查...${NC}"
    
    # 重启服务触发检查
    systemctl restart $SERVICE_NAME
    
    echo -e "${GREEN}已触发检查，请查看日志了解结果${NC}"
    echo -e "${CYAN}查看实时日志...${NC}"
    
    # 等待服务启动
    sleep 3
    
    # 显示日志
    timeout 30 tail -f $INSTALL_DIR/logs/monitor.log | while read line; do
        echo "$line"
        if echo "$line" | grep -q "域名检查完成"; then
            break
        fi
    done
}

change_interval() {
    echo -e "${BLUE}修改检查间隔${NC}"
    
    current=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('check_interval', 60))" 2>/dev/null)
    echo -e "${CYAN}当前检查间隔: $current 分钟${NC}"
    echo
    echo "建议值:"
    echo "  5  - 紧急监控 (域名即将释放)"
    echo "  15 - 高频监控 (重要域名)"
    echo "  30 - 常规监控"
    echo "  60 - 标准监控 (默认)"
    echo "  120 - 低频监控 (一般关注)"
    echo "  360 - 每日检查 (长期关注)"
    echo
    
    read -p "请输入新的检查间隔（分钟）: " interval
    
    if [[ "$interval" =~ ^[0-9]+$ ]] && [ $interval -ge 1 ] && [ $interval -le 1440 ]; then
        python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
config['check_interval'] = $interval
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
        echo -e "${GREEN}检查间隔已更新为 $interval 分钟${NC}"
        systemctl restart $SERVICE_NAME
    else
        echo -e "${RED}无效的间隔时间（1-1440分钟）${NC}"
    fi
}

view_history() {
    echo -e "${BLUE}查看检查历史${NC}"
    
    if [[ ! -f "$INSTALL_DIR/history.json" ]]; then
        echo -e "${YELLOW}暂无历史记录${NC}"
        return
    fi
    
    python3 << EOF
import json
from datetime import datetime

try:
    with open('$INSTALL_DIR/history.json', 'r') as f:
        history = json.load(f)
    
    if not history:
        print("暂无历史记录")
    else:
        print(f"共有 {len(history)} 个域名的历史记录\\n")
        
        # 分类统计
        available_count = sum(1 for d in history.values() if d.get('status') == 'available')
        registered_count = sum(1 for d in history.values() if d.get('status') == 'registered')
        expired_count = sum(1 for d in history.values() if d.get('status') == 'expired')
        
        print(f"统计信息:")
        print(f"  可注册: {available_count} 个")
        print(f"  已注册: {registered_count} 个")
        print(f"  已过期: {expired_count} 个")
        print()
        
        for domain, info in sorted(history.items()):
            print(f"域名: {domain}")
            
            status = info.get('status', 'unknown')
            status_emoji = {
                'available': '✅',
                'registered': '❌',
                'expired': '💀',
                'error': '⚠️'
            }.get(status, '❓')
            
            print(f"  状态: {status_emoji} {status}")
            
            last_check = info.get('last_check', '')
            if last_check:
                try:
                    check_time = datetime.fromisoformat(last_check)
                    print(f"  最后检查: {check_time.strftime('%Y-%m-%d %H:%M:%S')}")
                    # 计算距离现在的时间
                    time_diff = datetime.now() - check_time
                    if time_diff.days > 0:
                        print(f"  距今: {time_diff.days} 天前")
                    else:
                        hours = time_diff.seconds // 3600
                        minutes = (time_diff.seconds % 3600) // 60
                        print(f"  距今: {hours} 小时 {minutes} 分钟前")
                except:
                    print(f"  最后检查: {last_check}")
                    
            if info.get('expiry_date'):
                print(f"  过期时间: {info.get('expiry_date')}")
                
            if info.get('days_until_expiry') is not None:
                days = info.get('days_until_expiry')
                if days < 0:
                    print(f"  状态: 已过期 {abs(days)} 天")
                elif days == 0:
                    print(f"  状态: 今天过期!")
                else:
                    print(f"  剩余天数: {days} 天")
                
            if info.get('last_notified'):
                print(f"  最后通知: {info.get('last_notified')}")
                
            print()
except Exception as e:
    print(f"读取历史记录失败: {e}")
EOF
}

advanced_settings() {
    echo -e "${BLUE}高级设置${NC}"
    echo -e "${GREEN}1.${NC} 设置过期提醒天数"
    echo -e "${GREEN}2.${NC} 清理历史记录"
    echo -e "${GREEN}3.${NC} 导出域名列表"
    echo -e "${GREEN}4.${NC} 导入域名列表"
    echo -e "${GREEN}5.${NC} 查看系统信息"
    echo -e "${GREEN}0.${NC} 返回主菜单"
    echo
    read -p "请选择操作: " choice
    
    case $choice in
        1)
            echo -e "${CYAN}设置域名过期前多少天发送提醒${NC}"
            current_days=$(python3 -c "import json; print(json.load(open('$CONFIG_FILE')).get('notify_days_before_expiry', [30,7,3,1]))" 2>/dev/null)
            echo "当前设置: $current_days"
            echo "请输入提醒天数（用空格分隔，如: 30 7 3 1）:"
            read -a days_array
            if [ ${#days_array[@]} -gt 0 ]; then
                python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
config['notify_days_before_expiry'] = [${days_array[@]}]
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
                echo -e "${GREEN}提醒天数已更新${NC}"
            fi
            ;;
        2)
            echo -e "${YELLOW}清理历史记录${NC}"
            read -p "确定要清理所有历史记录吗? (yes/no): " confirm
            if [[ "$confirm" == "yes" ]]; then
                echo '{}' > $INSTALL_DIR/history.json
                echo -e "${GREEN}历史记录已清理${NC}"
            fi
            ;;
        3)
            echo -e "${CYAN}导出域名列表${NC}"
            if [[ -f "$DOMAINS_FILE" ]]; then
                cp "$DOMAINS_FILE" "/tmp/domainmonitor_domains_$(date +%Y%m%d_%H%M%S).txt"
                echo -e "${GREEN}域名列表已导出到: /tmp/domainmonitor_domains_$(date +%Y%m%d_%H%M%S).txt${NC}"
            else
                echo -e "${YELLOW}域名列表为空${NC}"
            fi
            ;;
        4)
            echo -e "${CYAN}导入域名列表${NC}"
            read -p "请输入要导入的文件路径: " import_file
            if [[ -f "$import_file" ]]; then
                while IFS= read -r domain; do
                    domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
                    if validate_domain "$domain" && ! grep -q "^$domain$" "$DOMAINS_FILE"; then
                        echo "$domain" >> "$DOMAINS_FILE"
                        echo -e "${GREEN}✓ 导入: $domain${NC}"
                    fi
                done < "$import_file"
                echo -e "${GREEN}导入完成${NC}"
                systemctl restart $SERVICE_NAME
            else
                echo -e "${RED}文件不存在${NC}"
            fi
            ;;
        5)
            echo -e "${CYAN}系统信息${NC}"
            echo "安装目录: $INSTALL_DIR"
            echo "配置文件: $CONFIG_FILE"
            echo "域名列表: $DOMAINS_FILE"
            echo "日志文件: $INSTALL_DIR/logs/monitor.log"
            echo
            echo "Python版本:"
            python3 --version
            echo
            echo "已安装的Python包:"
            pip3 list | grep -E "requests|schedule|python-telegram-bot"
            ;;
    esac
}

uninstall() {
    echo -e "${RED}警告: 此操作将删除所有配置和数据！${NC}"
    echo -e "${YELLOW}将删除:${NC}"
    echo "  - 监控服务"
    echo "  - 所有配置文件"
    echo "  - 监控域名列表"
    echo "  - 历史记录"
    echo "  - 日志文件"
    echo
    read -p "确定要卸载吗? (yes/no): " confirm
    
    if [[ "$confirm" == "yes" ]]; then
        echo -e "${YELLOW}正在卸载...${NC}"
        
        # 停止和删除服务
        systemctl stop $SERVICE_NAME
        systemctl disable $SERVICE_NAME
        rm -f /etc/systemd/system/$SERVICE_NAME.service
        systemctl daemon-reload
        
        # 备份数据
        if [[ -d "$INSTALL_DIR" ]]; then
            backup_file="/tmp/domainmonitor_backup_$(date +%Y%m%d_%H%M%S).tar.gz"
            tar -czf "$backup_file" -C /opt domainmonitor 2>/dev/null
            echo -e "${CYAN}数据已备份到: $backup_file${NC}"
        fi
        
        # 删除目录
        rm -rf $INSTALL_DIR
        
        echo -e "${GREEN}域名监控系统已卸载${NC}"
        echo -e "${YELLOW}感谢使用！${NC}"
        exit 0
    else
        echo -e "${YELLOW}取消卸载${NC}"
    fi
}

# 主循环
while true; do
    show_menu
    read -p "请选择操作 [0-13]: " choice
    
    case $choice in
        1) add_domain ;;
        2) delete_domain ;;
        3) configure_telegram ;;
        4) delete_telegram ;;
        5) list_domains ;;
        6) check_status ;;
        7) restart_service ;;
        8) view_logs ;;
        9) check_now ;;
        10) change_interval ;;
        11) view_history ;;
        12) advanced_settings ;;
        13) uninstall ;;
        0) 
            echo -e "${GREEN}感谢使用域名监控系统！${NC}"
            exit 0 
            ;;
        *) echo -e "${RED}无效的选择${NC}" ;;
    esac
    
    echo
    read -p "按Enter键继续..."
done
EOF
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
StandardOutput=append:$LOG_DIR/monitor.log
StandardError=append:$LOG_DIR/monitor.log

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
    
    # 创建默认配置文件
    cat > $CONFIG_FILE << EOF
{
  "telegram": {
    "bot_token": "",
    "chat_id": ""
  },
  "check_interval": 60,
  "notify_days_before_expiry": [30, 7, 3, 1]
}
EOF
    
    # 创建空域名文件
    touch $DOMAINS_FILE
    
    # 创建空历史文件
    echo '{}' > $INSTALL_DIR/history.json
    
    print_success "配置初始化完成"
}

# 验证域名格式（用于向导）
validate_domain() {
    local domain=$1
    if [[ $domain =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$ ]]; then
        return 0
    else
        return 1
    fi
}

# 配置向导
configuration_wizard() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}        域名监控系统配置向导           ${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo
    
    # 添加域名
    echo -e "${CYAN}步骤 1/3: 添加监控域名${NC}"
    read -p "请输入要监控的域名 (多个域名用空格分隔，可直接回车跳过): " domains
    if [[ -n "$domains" ]]; then
        for domain in $domains; do
            domain=$(echo "$domain" | tr '[:upper:]' '[:lower:]')
            if validate_domain "$domain"; then
                echo "$domain" >> $DOMAINS_FILE
                print_success "添加域名: $domain"
            else
                print_warning "跳过无效域名: $domain"
            fi
        done
    fi
    
    # 配置Telegram
    echo
    echo -e "${CYAN}步骤 2/3: 配置Telegram通知${NC}"
    read -p "是否现在配置Telegram通知? (y/n): " setup_telegram
    if [[ "$setup_telegram" == "y" ]]; then
        echo
        echo -e "${YELLOW}获取Telegram Bot Token和Chat ID的方法:${NC}"
        echo "1. 在Telegram中搜索 @BotFather"
        echo "2. 发送 /newbot 创建新机器人"
        echo "3. 按提示设置机器人名称和用户名"
        echo "4. 获得Bot Token (类似: 1234567890:ABCdefGHIjklMNOpqrsTUVwxyz)"
        echo "5. 搜索您的机器人并发送任意消息"
        echo "6. 访问 https://api.telegram.org/bot<BOT_TOKEN>/getUpdates"
        echo "7. 在返回的JSON中找到 \"chat\":{\"id\":数字}"
        echo
        
        read -p "请输入Bot Token: " bot_token
        read -p "请输入Chat ID: " chat_id
        
        if [[ -n "$bot_token" ]] && [[ -n "$chat_id" ]]; then
            # 验证配置
            response=$(curl -s "https://api.telegram.org/bot$bot_token/getMe")
            if echo "$response" | grep -q '"ok":true'; then
                python3 -c "
import json
config = {
    'telegram': {'bot_token': '$bot_token', 'chat_id': '$chat_id'},
    'check_interval': 60,
    'notify_days_before_expiry': [30, 7, 3, 1]
}
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
                print_success "Telegram配置完成"
                
                # 发送测试通知
                echo
                print_info "发送测试通知..."
                curl -s -X POST "https://api.telegram.org/bot$bot_token/sendMessage" \
                     -d "chat_id=$chat_id" \
                     -d "text=✅ <b>域名监控系统安装成功！</b>%0A%0A系统将每60分钟检查一次域名状态。" \
                     -d "parse_mode=HTML" > /dev/null
                print_success "测试通知已发送"
            else
                print_error "Bot Token验证失败，请检查是否正确"
            fi
        fi
    fi
    
    # 设置检查间隔
    echo
    echo -e "${CYAN}步骤 3/3: 设置检查间隔${NC}"
    echo "推荐设置:"
    echo "  - 紧急监控: 5-15分钟"
    echo "  - 常规监控: 30-60分钟"
    echo "  - 长期关注: 120-360分钟"
    read -p "请输入检查间隔(分钟，默认60): " interval
    
    if [[ -n "$interval" ]] && [[ "$interval" =~ ^[0-9]+$ ]]; then
        python3 -c "
import json
with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)
config['check_interval'] = $interval
with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=2)
"
        print_success "检查间隔设置为 $interval 分钟"
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
    echo -e "${GREEN}"
    cat << 'EOF'
    ___                   _       
   |_ _|_ __  ___| |_ __ _| | | 
    | || '_ \/ __| __/ _` | | |
    | || | | \__ \ || (_| | | |
   |___|_| |_|___/\__\__,_|_|_|
   
   ____                      _      _       _ 
  / ___|___  _ __ ___  _ __ | | ___| |_ ___| |
 | |   / _ \| '_ ` _ \| '_ \| |/ _ \ __/ _ \ |
 | |__| (_) | | | | | | |_) | |  __/ ||  __/_|
  \____\___/|_| |_| |_| .__/|_|\___|\__\___(_)
                      |_|                      
EOF
    echo -e "${NC}"
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
    echo "• 🚀 支持批量域名监控"
    echo "• 🔄 灵活的检查间隔设置"
    echo
    echo -e "${CYAN}项目地址:${NC} https://github.com/everett7623/domainmonitor"
    echo
    echo -e "${GREEN}立即运行 ${YELLOW}/opt/domainmonitor/manage.sh${GREEN} 开始管理域名监控${NC}"
}

# 主安装流程
main() {
    show_logo
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
