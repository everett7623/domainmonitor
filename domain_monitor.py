#!/usr/bin/env python3
# -*- coding: utf-8 -*-

"""
============================================================================
域名监控系统 - 核心监控程序
作者: everett7623
GitHub: https://github.com/everett7623/domainmonitor
描述: 自动监控域名注册状态，支持Telegram通知
============================================================================
"""

import json
import logging
import os
import sys
import time
import socket
import datetime
import traceback
from typing import Dict, List, Optional, Tuple

# 导入依赖
try:
    import schedule
    import requests
    import whois
except ImportError as e:
    print(f"错误: 缺少必要的Python包 - {e}")
    print("请运行: pip3 install requests python-whois schedule")
    sys.exit(1)

# 尝试导入Rich（可选）
try:
    from rich.console import Console
    from rich.table import Table
    from rich.progress import Progress, SpinnerColumn, TextColumn
    from rich.logging import RichHandler
    RICH_AVAILABLE = True
    console = Console()
except ImportError:
    RICH_AVAILABLE = False
    console = None

# 配置文件路径
CONFIG_FILE = "/opt/domainmonitor/config.json"
DATA_DIR = "/opt/domainmonitor/data"
LOG_DIR = "/var/log/domainmonitor"

# 日志配置
if RICH_AVAILABLE:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
        handlers=[
            RichHandler(console=console, rich_tracebacks=True),
            logging.FileHandler(f"{LOG_DIR}/monitor.log", encoding='utf-8')
        ]
    )
else:
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
        logger.info(f"📱 Telegram通知已配置 (Chat ID: {chat_id})")
        
    def send_message(self, message: str, parse_mode: str = "HTML") -> bool:
        """发送Telegram消息"""
        try:
            data = {
                "chat_id": self.chat_id,
                "text": message,
                "parse_mode": parse_mode,
                "disable_web_page_preview": False
            }
            
            logger.debug(f"发送Telegram消息到 {self.chat_id}")
            response = requests.post(
                f"{self.api_url}/sendMessage",
                json=data,
                timeout=10
            )
            
            if response.status_code == 200:
                logger.info("✅ Telegram通知发送成功")
                return True
            else:
                logger.error(f"❌ Telegram通知失败: {response.status_code} - {response.text}")
                return False
                
        except Exception as e:
            logger.error(f"❌ Telegram通知异常: {str(e)}")
            return False
    
    def format_available_notification(self, domain: str, check_time: str, 
                                     registrars: List[Dict]) -> str:
        """格式化可注册域名通知"""
        message = f"""
🎯 <b>域名可注册提醒</b> 🎯

━━━━━━━━━━━━━━━━━━━━━━
📍 <b>域名:</b> <code>{domain}</code>
🟢 <b>状态:</b> <u>可以注册</u>
⏰ <b>检测时间:</b> {check_time}
━━━━━━━━━━━━━━━━━━━━━━

<b>🏪 推荐注册商:</b>
"""
        for i, registrar in enumerate(registrars[:4], 1):
            features = ", ".join(registrar.get("features", []))
            message += f"""
{i}. <b>{registrar['name']}</b>
   🔗 {registrar['url']}
   ✨ 特点: {features}
"""
        
        message += """
━━━━━━━━━━━━━━━━━━━━━━
<b>💡 注册建议:</b>
• 建议注册 3-5 年以获得优惠
• 开启域名隐私保护
• 配置自动续费避免过期
• 立即注册以免被他人抢注

⚡ <b>紧急提醒: 请尽快注册!</b>
━━━━━━━━━━━━━━━━━━━━━━
"""
        return message
    
    def format_status_change_notification(self, domain: str, old_status: str, 
                                         new_status: str, check_time: str) -> str:
        """格式化状态变更通知"""
        status_emoji = {
            "available": "🟢",
            "registered": "🔴",
            "unknown": "⚪"
        }
        
        status_text = {
            "available": "可注册",
            "registered": "已注册",
            "unknown": "未知"
        }
        
        message = f"""
🔄 <b>域名状态变更</b> 🔄

━━━━━━━━━━━━━━━━━━━━━━
📍 <b>域名:</b> <code>{domain}</code>
📊 <b>原状态:</b> {status_emoji.get(old_status, '⚪')} {status_text.get(old_status, old_status)}
📊 <b>新状态:</b> {status_emoji.get(new_status, '⚪')} {status_text.get(new_status, new_status)}
⏰ <b>检测时间:</b> {check_time}
━━━━━━━━━━━━━━━━━━━━━━
"""
        
        if new_status == "available":
            message += """
✅ <b>好消息!</b> 域名现在可以注册了!
💡 建议立即行动，避免被他人抢注
"""
        elif new_status == "registered" and old_status == "available":
            message += """
❌ <b>遗憾!</b> 域名已被他人注册
💡 您可以考虑其他后缀或相似域名
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
            try:
                with open(self.history_file, 'r') as f:
                    self.history = json.load(f)
            except:
                self.history = {}
        else:
            self.history = {}
    
    def save_history(self):
        """保存历史记录"""
        try:
            with open(self.history_file, 'w') as f:
                json.dump(self.history, f, indent=4)
        except Exception as e:
            logger.error(f"保存历史记录失败: {str(e)}")
    
    def check_domain_status(self, domain: str) -> Tuple[str, Optional[Dict]]:
        """
        检查域名状态
        返回: (status, whois_info)
        status: 'available', 'registered', 'unknown'
        """
        logger.info(f"🔎 正在查询域名: {domain}")
        
        try:
            # 首先尝试DNS解析
            dns_exists = False
            try:
                socket.gethostbyname(domain)
                dns_exists = True
                logger.debug(f"DNS解析成功: {domain}")
            except socket.gaierror:
                logger.debug(f"DNS解析失败: {domain}")
                dns_exists = False
            
            # 查询WHOIS信息
            try:
                logger.debug(f"开始WHOIS查询: {domain}")
                w = whois.whois(domain)
                
                # 判断域名状态
                # 检查多个字段来确定是否已注册
                is_registered = False
                
                if w:
                    # 检查关键字段
                    if hasattr(w, 'domain_name') and w.domain_name:
                        is_registered = True
                    elif hasattr(w, 'registrar') and w.registrar:
                        is_registered = True
                    elif hasattr(w, 'creation_date') and w.creation_date:
                        is_registered = True
                    elif hasattr(w, 'status') and w.status:
                        is_registered = True
                
                if is_registered:
                    logger.info(f"✅ WHOIS查询成功: {domain} - 已注册")
                    whois_info = {
                        "registrar": getattr(w, 'registrar', None),
                        "creation_date": str(getattr(w, 'creation_date', None)),
                        "expiration_date": str(getattr(w, 'expiration_date', None)),
                        "status": getattr(w, 'status', None)
                    }
                    return ("registered", whois_info)
                else:
                    logger.info(f"✅ WHOIS查询成功: {domain} - 可注册")
                    return ("available", None)
                    
            except whois.parser.PywhoisError as e:
                # WHOIS明确返回域名不存在
                logger.info(f"✅ 域名未注册: {domain}")
                return ("available", None)
            except Exception as e:
                logger.warning(f"WHOIS查询异常: {str(e)}")
                # WHOIS查询失败，根据DNS判断
                if not dns_exists:
                    logger.info(f"根据DNS判断: {domain} - 可能可注册")
                    return ("available", None)
                else:
                    logger.info(f"无法确定状态: {domain}")
                    return ("unknown", None)
                    
        except Exception as e:
            logger.error(f"检查域名 {domain} 时出错: {str(e)}")
            return ("unknown", None)
    
    def update_history(self, domain: str, status: str, whois_info: Optional[Dict]):
        """更新历史记录"""
        if domain not in self.history:
            self.history[domain] = {
                "first_check": datetime.datetime.now().isoformat(),
                "checks": [],
                "notification_sent": False  # 添加通知标记
            }
        
        check_record = {
            "time": datetime.datetime.now().isoformat(),
            "status": status,
            "whois_info": whois_info
        }
        
        self.history[domain]["checks"].append(check_record)
        self.history[domain]["last_status"] = status
        self.history[domain]["last_check"] = datetime.datetime.now().isoformat()
        
        # 只保留最近100条记录
        if len(self.history[domain]["checks"]) > 100:
            self.history[domain]["checks"] = self.history[domain]["checks"][-100:]
        
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
            logger.info("✅ Telegram通知已启用")
        else:
            self.notifier = None
            logger.info("⚠️ Telegram通知未启用")
            
        logger.info("🚀 域名监控系统启动成功")
    
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
        logger.info(f"🔍 开始检查域名: {domain}")
        
        # 获取之前的状态
        old_status = None
        notification_sent = False
        
        if domain in self.checker.history:
            old_status = self.checker.history[domain].get("last_status")
            notification_sent = self.checker.history[domain].get("notification_sent", False)
        
        # 检查当前状态
        status, whois_info = self.checker.check_domain_status(domain)
        
        # 更新历史记录
        self.checker.update_history(domain, status, whois_info)
        
        # 记录状态
        status_emoji = {
            "available": "🟢",
            "registered": "🔴",
            "unknown": "⚪"
        }
        logger.info(f"{status_emoji.get(status, '⚪')} 域名状态 - {domain}: {status}")
        
        # 发送通知
        if self.notifier:
            current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            
            # 发送通知的条件：
            # 1. 域名可注册且之前没有发送过通知
            # 2. 状态发生变化
            
            if status == "available":
                # 如果域名可注册
                if not notification_sent or (old_status and old_status != "available"):
                    logger.info(f"📨 准备发送可注册通知: {domain}")
                    message = self.notifier.format_available_notification(
                        domain, current_time, self.config.get("registrars", [])
                    )
                    if self.notifier.send_message(message):
                        # 标记已发送通知
                        self.checker.history[domain]["notification_sent"] = True
                        self.checker.save_history()
                        logger.info(f"✅ 已发送可注册通知: {domain}")
                    else:
                        logger.error(f"❌ 发送通知失败: {domain}")
                else:
                    logger.info(f"ℹ️ 域名 {domain} 可注册，但已发送过通知")
            
            elif old_status and old_status != status:
                # 状态变化通知
                logger.info(f"📨 准备发送状态变更通知: {domain} ({old_status} -> {status})")
                message = self.notifier.format_status_change_notification(
                    domain, old_status, status, current_time
                )
                if self.notifier.send_message(message):
                    logger.info(f"✅ 已发送状态变更通知: {domain}")
                    # 如果变为不可注册，重置通知标记
                    if status != "available":
                        self.checker.history[domain]["notification_sent"] = False
                        self.checker.save_history()
        else:
            logger.warning("⚠️ Telegram通知未配置，跳过通知发送")
    
    def check_all_domains(self):
        """检查所有域名"""
        domains = self.config.get("domains", [])
        
        if not domains:
            logger.warning("⚠️ 没有配置要监控的域名")
            return
        
        logger.info(f"📋 开始检查 {len(domains)} 个域名")
        logger.info(f"📝 域名列表: {', '.join(domains)}")
        
        for i, domain in enumerate(domains, 1):
            logger.info(f"[{i}/{len(domains)}] 检查域名: {domain}")
            try:
                self.check_single_domain(domain)
            except Exception as e:
                logger.error(f"❌ 检查域名 {domain} 失败: {str(e)}")
                logger.debug(traceback.format_exc())
            
            # 避免请求过快
            if i < len(domains):
                time.sleep(2)
        
        logger.info("✅ 所有域名检查完成")
        logger.info("=" * 60)
    
    def run_scheduler(self):
        """运行定时任务"""
        # 立即执行一次
        self.check_all_domains()
        
        # 设置定时任务
        interval = self.config.get("check_interval", 3600)  # 默认1小时
        schedule.every(interval).seconds.do(self.check_all_domains)
        
        logger.info(f"⏰ 定时任务已设置，每 {interval} 秒检查一次")
        
        # 运行调度器
        while True:
            try:
                schedule.run_pending()
                time.sleep(60)  # 每分钟检查一次是否有任务
            except KeyboardInterrupt:
                logger.info("🛑 监控系统停止")
                break
            except Exception as e:
                logger.error(f"❌ 运行时错误: {str(e)}")
                logger.debug(traceback.format_exc())
                time.sleep(60)


def main():
    """主函数"""
    try:
        # 确保目录存在
        os.makedirs(DATA_DIR, exist_ok=True)
        os.makedirs(LOG_DIR, exist_ok=True)
        
        # 启动监控
        monitor = DomainMonitor()
        monitor.run_scheduler()
        
    except KeyboardInterrupt:
        logger.info("🛑 程序被用户中断")
        sys.exit(0)
    except Exception as e:
        logger.error(f"❌ 程序异常退出: {str(e)}")
        logger.debug(traceback.format_exc())
        sys.exit(1)


if __name__ == "__main__":
    main()
