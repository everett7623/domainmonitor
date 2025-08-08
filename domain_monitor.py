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
import schedule
import requests
import whois
from rich.console import Console
from rich.table import Table
from rich.progress import Progress, SpinnerColumn, TextColumn
from rich.logging import RichHandler

# 配置文件路径
CONFIG_FILE = "/opt/domainmonitor/config.json"
DATA_DIR = "/opt/domainmonitor/data"
LOG_DIR = "/var/log/domainmonitor"

# 创建Rich控制台
console = Console()

# 日志配置
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        RichHandler(console=console, rich_tracebacks=True),
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
    
    def format_expiring_notification(self, domain: str, expiry_date: str, 
                                    days_left: int) -> str:
        """格式化域名即将到期通知"""
        urgency = "🔴 紧急" if days_left <= 7 else "🟡 重要" if days_left <= 30 else "🟢 提醒"
        
        message = f"""
⏰ <b>域名到期提醒</b> ⏰

━━━━━━━━━━━━━━━━━━━━━━
📍 <b>域名:</b> <code>{domain}</code>
📅 <b>到期时间:</b> {expiry_date}
⏳ <b>剩余天数:</b> {days_left} 天
🚨 <b>紧急程度:</b> {urgency}
━━━━━━━━━━━━━━━━━━━━━━

<b>⚠️ 注意事项:</b>
• 请尽快续费避免域名过期
• 过期后有赎回期，费用较高
• 过期域名可能被他人抢注
• 建议开启自动续费功能

<b>📝 续费建议:</b>
• 一次续费多年可获优惠
• 检查DNS和SSL证书配置
• 更新域名联系信息
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
        
        message = f"""
🔄 <b>域名状态变更</b> 🔄

━━━━━━━━━━━━━━━━━━━━━━
📍 <b>域名:</b> <code>{domain}</code>
📊 <b>原状态:</b> {status_emoji.get(old_status, '⚪')} {old_status}
📊 <b>新状态:</b> {status_emoji.get(new_status, '⚪')} {new_status}
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
            with open(self.history_file, 'r') as f:
                self.history = json.load(f)
        else:
            self.history = {}
    
    def save_history(self):
        """保存历史记录"""
        with open(self.history_file, 'w') as f:
            json.dump(self.history, f, indent=4)
    
    def check_domain_status(self, domain: str) -> Tuple[str, Optional[Dict]]:
        """
        检查域名状态
        返回: (status, whois_info)
        status: 'available', 'registered', 'unknown'
        """
        try:
            # 首先尝试DNS解析
            try:
                socket.gethostbyname(domain)
                dns_exists = True
            except socket.gaierror:
                dns_exists = False
            
            # 查询WHOIS信息
            try:
                w = whois.whois(domain)
                
                # 判断域名状态
                if w.domain_name:
                    # 域名已注册
                    expiry_date = None
                    if w.expiration_date:
                        if isinstance(w.expiration_date, list):
                            expiry_date = w.expiration_date[0]
                        else:
                            expiry_date = w.expiration_date
                    
                    whois_info = {
                        "registrar": w.registrar,
                        "creation_date": str(w.creation_date) if w.creation_date else None,
                        "expiration_date": str(expiry_date) if expiry_date else None,
                        "name_servers": w.name_servers if w.name_servers else [],
                        "status": w.status if w.status else []
                    }
                    
                    return ("registered", whois_info)
                else:
                    # 域名可能未注册
                    return ("available", None)
                    
            except Exception as e:
                # WHOIS查询失败，根据DNS判断
                if not dns_exists:
                    return ("available", None)
                else:
                    return ("unknown", None)
                    
        except Exception as e:
            logger.error(f"检查域名 {domain} 时出错: {str(e)}")
            return ("unknown", None)
    
    def check_expiry(self, whois_info: Dict) -> Optional[int]:
        """检查域名到期时间，返回剩余天数"""
        if not whois_info or not whois_info.get("expiration_date"):
            return None
            
        try:
            expiry_str = whois_info["expiration_date"]
            # 解析日期
            if isinstance(expiry_str, str):
                # 尝试多种日期格式
                for fmt in ["%Y-%m-%d %H:%M:%S", "%Y-%m-%d", "%d-%m-%Y"]:
                    try:
                        expiry_date = datetime.datetime.strptime(
                            expiry_str.split()[0], fmt
                        )
                        break
                    except:
                        continue
                else:
                    return None
            else:
                expiry_date = expiry_str
                
            # 计算剩余天数
            days_left = (expiry_date - datetime.datetime.now()).days
            return days_left
            
        except Exception as e:
            logger.error(f"解析到期时间失败: {str(e)}")
            return None
    
    def update_history(self, domain: str, status: str, whois_info: Optional[Dict]):
        """更新历史记录"""
        if domain not in self.history:
            self.history[domain] = {
                "first_check": datetime.datetime.now().isoformat(),
                "checks": []
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
        
        # 记录状态
        status_emoji = {
            "available": "🟢",
            "registered": "🔴",
            "unknown": "⚪"
        }
        logger.info(f"{status_emoji.get(status, '⚪')} {domain}: {status}")
        
        # 发送通知
        if self.notifier:
            current_time = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
            
            # 状态变更通知
            if old_status and old_status != status:
                message = self.notifier.format_status_change_notification(
                    domain, old_status, status, current_time
                )
                self.notifier.send_message(message)
            
            # 可注册通知
            if status == "available":
                message = self.notifier.format_available_notification(
                    domain, current_time, self.config.get("registrars", [])
                )
                self.notifier.send_message(message)
            
            # 即将到期通知
            elif status == "registered" and whois_info:
                days_left = self.checker.check_expiry(whois_info)
                if days_left and days_left <= 60:  # 60天内到期
                    expiry_date = whois_info.get("expiration_date", "未知")
                    message = self.notifier.format_expiring_notification(
                        domain, expiry_date, days_left
                    )
                    self.notifier.send_message(message)
    
    def check_all_domains(self):
        """检查所有域名"""
        domains = self.config.get("domains", [])
        
        if not domains:
            logger.warning("⚠️ 没有配置要监控的域名")
            return
        
        logger.info(f"📋 开始检查 {len(domains)} 个域名")
        
        with Progress(
            SpinnerColumn(),
            TextColumn("[progress.description]{task.description}"),
            console=console
        ) as progress:
            task = progress.add_task("检查域名...", total=len(domains))
            
            for domain in domains:
                progress.update(task, description=f"检查: {domain}")
                try:
                    self.check_single_domain(domain)
                except Exception as e:
                    logger.error(f"❌ 检查域名 {domain} 失败: {str(e)}")
                    logger.debug(traceback.format_exc())
                
                progress.advance(task)
                time.sleep(2)  # 避免请求过快
        
        logger.info("✅ 所有域名检查完成")
    
    def display_status(self):
        """显示当前状态"""
        table = Table(title="域名监控状态", show_header=True, header_style="bold magenta")
        table.add_column("域名", style="cyan", no_wrap=True)
        table.add_column("状态", justify="center")
        table.add_column("最后检查", style="yellow")
        table.add_column("到期时间", style="red")
        
        for domain in self.config.get("domains", []):
            if domain in self.checker.history:
                history = self.checker.history[domain]
                status = history.get("last_status", "未知")
                last_check = history.get("last_check", "从未")
                
                # 获取到期时间
                expiry = "N/A"
                if history.get("checks"):
                    last_record = history["checks"][-1]
                    if last_record.get("whois_info"):
                        expiry = last_record["whois_info"].get("expiration_date", "N/A")
                
                # 状态显示
                status_display = {
                    "available": "[green]可注册[/green]",
                    "registered": "[red]已注册[/red]",
                    "unknown": "[yellow]未知[/yellow]"
                }.get(status, status)
                
                # 格式化时间
                if last_check != "从未":
                    try:
                        dt = datetime.datetime.fromisoformat(last_check)
                        last_check = dt.strftime("%Y-%m-%d %H:%M")
                    except:
                        pass
                
                table.add_row(domain, status_display, last_check, expiry)
            else:
                table.add_row(domain, "[yellow]未检查[/yellow]", "从未", "N/A")
        
        console.print(table)
    
    def run_scheduler(self):
        """运行定时任务"""
        # 立即执行一次
        self.check_all_domains()
        
        # 设置定时任务
        interval = self.config.get("check_interval", 3600)  # 默认1小时
        schedule.every(interval).seconds.do(self.check_all_domains)
        
        logger.info(f"⏰ 定时任务已设置，每 {interval} 秒检查一次")
        
        # 显示初始状态
        self.display_status()
        
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
