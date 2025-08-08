#!/bin/bash

# ============================================================================
# 域名监控系统 - 快速修复脚本
# 作者: everett7623
# 描述: 修复Python依赖和通知问题
# ============================================================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${CYAN}      域名监控系统 - 快速修复工具          ${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo

# 检查root权限
if [[ $EUID -ne 0 ]]; then
   echo -e "${RED}❌ 请使用root权限运行${NC}"
   echo -e "${YELLOW}请使用: sudo bash $0${NC}"
   exit 1
fi

echo -e "${BLUE}🔧 开始修复...${NC}"
echo

# 1. 停止服务
echo -e "${YELLOW}⏸️  停止监控服务...${NC}"
systemctl stop domainmonitor 2>/dev/null

# 2. 升级pip
echo -e "${BLUE}📦 升级pip和setuptools...${NC}"
pip3 install --upgrade pip setuptools wheel

# 3. 卸载旧包
echo -e "${BLUE}🗑️  清理旧的Python包...${NC}"
pip3 uninstall -y telegram-python-bot python-telegram-bot 2>/dev/null

# 4. 重新安装依赖
echo -e "${BLUE}📚 重新安装Python依赖...${NC}"
pip3 install --no-cache-dir requests
pip3 install --no-cache-dir python-whois
pip3 install --no-cache-dir python-telegram-bot
pip3 install --no-cache-dir schedule
pip3 install --no-cache-dir colorama
pip3 install --no-cache-dir rich

# 5. 下载修复后的程序
echo -e "${BLUE}⬇️  下载修复版本...${NC}"
cd /opt/domainmonitor

# 备份旧文件
cp domain_monitor.py domain_monitor.py.backup 2>/dev/null

# 创建新的监控程序（使用修复后的版本）
cat > domain_monitor_temp.py << 'PYTHON_EOF'
#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import json
import logging
import os
import sys
import time
import socket
import datetime
import traceback
from typing import Dict, List, Optional, Tuple

try:
    import schedule
    import requests
    import whois
except ImportError as e:
    print(f"错误: 缺少必要的Python包 - {e}")
    print("请运行修复脚本或手动安装: pip3 install requests python-whois schedule")
    sys.exit(1)

# 配置文件路径
CONFIG_FILE = "/opt/domainmonitor/config.json"
DATA_DIR = "/opt/domainmonitor/data"
LOG_DIR = "/var/log/domainmonitor"

# 日志配置
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.StreamHandler(),
        logging.FileHandler(f"{LOG_DIR}/monitor.log", encoding='utf-8')
    ]
)
logger = logging.getLogger("DomainMonitor")


class TelegramNotifier:
    """Telegram通知管理器"""
    
    def __init__(self, bot_token: str, chat_id: str):
        self.bot_token = bot_token
        self.chat_id = chat_id
        self.api_url = f"https://api.telegram.org/bot{bot_token}"
        
    def send_message(self, message: str, parse_mode: str = "HTML") -> bool:
        """发送Telegram消息"""
        try:
            data = {
                "chat_id": self.chat_id,
                "text": message,
                "parse_mode": parse_mode,
                "disable_web_page_preview": False
            }
            response = requests.post(
                f"{self.api_url}/sendMessage",
                json=data,
                timeout=10
            )
            if response.status_code == 200:
                logger.info("✅ Telegram通知发送成功")
                return True
            else:
                logger.error(f"❌ Telegram通知失败: {response.text}")
                return False
        except Exception as e:
            logger.error(f"❌ Telegram通知异常: {str(e)}")
            return False
    
    def format_available_notification(self, domain: str, check_time: str) -> str:
        """格式化可注册域名通知"""
        message = f"""
🎯 <b>域名可注册提醒</b> 🎯

━━━━━━━━━━━━━━━━━━━━━━
📍 <b>域名:</b> <code>{domain}</code>
🟢 <b>状态:</b> <u>可以注册</u>
⏰ <b>检测时间:</b> {check_time}
━━━━━━━━━━━━━━━━━━━━━━

⚡ <b>紧急提醒: 请尽快注册!</b>
━━━━━━━━━━━━━━━━━━━━━━
"""
        return message


class DomainChecker:
    """域名检查器"""
    
    def __init__(self):
        self.history_file = f"{DATA_DIR}/domain_history.json"
        self.load_history()
        
    def load_history(self):
        """加载历史记录"""
        if os.path.exists(self.history_file):
            with open(self.history_file, 'r') as f:
                self.history = json.load(f)
        else:
            self.history = {}
    
    def save_history(self):
        """保存历史记录"""
        with open(self.history_file, 'w') as f:
            json.dump(self.history, f, indent=4)
    
    def check_domain_status(self, domain: str) -> Tuple[str, Optional[Dict]]:
        """检查域名状态"""
        try:
            # DNS检查
            try:
                socket.gethostbyname(domain)
                dns_exists = True
            except:
                dns_exists = False
            
            # WHOIS查询
            try:
                w = whois.whois(domain)
                if w and (w.domain_name or w.registrar):
                    return ("registered", {"status": "registered"})
                else:
                    return ("available", None)
            except:
                if not dns_exists:
                    return ("available", None)
                else:
                    return ("unknown", None)
                    
        except Exception as e:
            logger.error(f"检查域名 {domain} 时出错: {str(e)}")
            return ("unknown", None)
    
    def update_history(self, domain: str, status: str, whois_info: Optional[Dict]):
        """更新历史记录"""
        if domain not in self.history:
            self.history[domain] = {
                "first_check": datetime.datetime.now().isoformat(),
                "checks": []
            }
        
        self.history[domain]["last_status"] = status
        self.history[domain]["last_check"] = datetime.datetime.now().isoformat()
        self.save_history()


class DomainMonitor:
    """域名监控主类"""
    
    def __init__(self):
        self.load_config()
        self.checker = DomainChecker()
        
        if self.config["telegram"]["enabled"]:
            self.notifier = TelegramNotifier(
                self.config["telegram"]["bot_token"],
                self.config["telegram"]["chat_id"]
            )
        else:
            self.notifier = None
            
        logger.info("🚀 域名监控系统启动")
    
    def load_config(self):
        """加载配置文件"""
        try:
            with open(CONFIG_FILE, 'r') as f:
                self.config = json.load(f)
            logger.info("✅ 配置文件加载成功")
        except Exception as e:
            logger.error(f"❌ 配置文件加载失败: {str(e)}")
            sys.exit(1)
    
    def check_single_domain(self, domain: str):
        """检查单个域名"""
        logger.info(f"🔍 检查域名: {domain}")
        
        # 获取之前的状态
        old_status = None
        if domain in self.checker.history:
            old_status = self.checker.history[domain].get("last_status")
        
        # 检查当前状态
        status, whois_info = self.checker.check_domain_status(domain)
        
        # 更新历史记录
        self.checker.update_history(domain, status, whois_info)
        
        logger.info(f"📊 {domain}: {status}")
        
        # 发送通知
        if self.notifier and status == "available":
            current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            message = self.notifier.format_available_notification(domain, current_time)
            self.notifier.send_message(message)
            logger.info(f"📨 已发送可注册通知: {domain}")
    
    def check_all_domains(self):
        """检查所有域名"""
        domains = self.config.get("domains", [])
        
        if not domains:
            logger.warning("⚠️ 没有配置要监控的域名")
            return
        
        logger.info(f"📋 开始检查 {len(domains)} 个域名")
        
        for domain in domains:
            try:
                self.check_single_domain(domain)
            except Exception as e:
                logger.error(f"❌ 检查域名 {domain} 失败: {str(e)}")
            time.sleep(2)
        
        logger.info("✅ 所有域名检查完成")
    
    def run_scheduler(self):
        """运行定时任务"""
        # 立即执行一次
        self.check_all_domains()
        
        # 设置定时任务
        interval = self.config.get("check_interval", 3600)
        schedule.every(interval).seconds.do(self.check_all_domains)
        
        logger.info(f"⏰ 定时任务已设置，每 {interval} 秒检查一次")
        
        while True:
            try:
                schedule.run_pending()
                time.sleep(60)
            except KeyboardInterrupt:
                logger.info("🛑 监控系统停止")
                break
            except Exception as e:
                logger.error(f"❌ 运行时错误: {str(e)}")
                time.sleep(60)


def main():
    """主函数"""
    try:
        os.makedirs(DATA_DIR, exist_ok=True)
        os.makedirs(LOG_DIR, exist_ok=True)
        
        monitor = DomainMonitor()
        monitor.run_scheduler()
        
    except KeyboardInterrupt:
        logger.info("🛑 程序被用户中断")
        sys.exit(0)
    except Exception as e:
        logger.error(f"❌ 程序异常退出: {str(e)}")
        sys.exit(1)


if __name__ == "__main__":
    main()
PYTHON_EOF

# 替换原文件
mv domain_monitor_temp.py domain_monitor.py
chmod +x domain_monitor.py

# 6. 测试Python环境
echo -e "${BLUE}🧪 测试Python环境...${NC}"
python3 -c "
import sys
print(f'Python版本: {sys.version}')
try:
    import requests
    print('✅ requests 已安装')
except:
    print('❌ requests 未安装')
try:
    import whois
    print('✅ python-whois 已安装')
except:
    print('❌ python-whois 未安装')
try:
    import schedule
    print('✅ schedule 已安装')
except:
    print('❌ schedule 未安装')
"

# 7. 重启服务
echo -e "${YELLOW}▶️  重启监控服务...${NC}"
systemctl daemon-reload
systemctl restart domainmonitor

sleep 2

# 8. 检查服务状态
if systemctl is-active --quiet domainmonitor; then
    echo -e "${GREEN}✅ 服务运行正常${NC}"
else
    echo -e "${RED}❌ 服务启动失败${NC}"
    echo -e "${YELLOW}查看错误日志: journalctl -u domainmonitor -n 50${NC}"
fi

echo
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo -e "${GREEN}🎉 修复完成！${NC}"
echo -e "${CYAN}═══════════════════════════════════════════${NC}"
echo
echo -e "${WHITE}测试命令:${NC}"
echo -e "${YELLOW}  domainctl test     # 测试Telegram通知${NC}"
echo -e "${YELLOW}  domainctl status   # 查看服务状态${NC}"
echo -e "${YELLOW}  domainctl logs     # 查看运行日志${NC}"
echo
