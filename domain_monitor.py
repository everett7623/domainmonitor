# -*- coding: utf-8 -*-
# =================================================================
# Project: domainmonitor
# Author: everett7623
# Description: 自动监控域名注册状态并通过 Telegram 通知
# Version: 1.0.0
# Github: https://github.com/everett7623/domainmonitor
# =================================================================

import whois
import schedule
import time
import logging
import sqlite3
import configparser
from telegram import Bot
from telegram.constants import ParseMode
from rich.logging import RichHandler
from rich.console import Console
from datetime import datetime, timedelta

# --- 初始化配置 ---
console = Console()
# 配置日志记录，同时输出到控制台和文件
logging.basicConfig(
    level="INFO",
    format="%(asctime)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("domain_monitor.log", mode='a', encoding='utf-8'),
        RichHandler(console=console, rich_tracebacks=True) # 使用 Rich 美化控制台输出
    ]
)

CONFIG_FILE = 'config.ini'
DB_FILE = 'db/history.db'

# --- 数据库管理 ---
def init_db():
    """初始化数据库和表"""
    with sqlite3.connect(DB_FILE) as conn:
        cursor = conn.cursor()
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS history (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                domain_name TEXT NOT NULL,
                status TEXT NOT NULL,
                check_time TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                details TEXT
            )
        ''')
        conn.commit()
    logging.info("数据库初始化完成。")

def log_to_db(domain_name, status, details=""):
    """将检测记录写入数据库"""
    with sqlite3.connect(DB_FILE) as conn:
        cursor = conn.cursor()
        cursor.execute(
            "INSERT INTO history (domain_name, status, details) VALUES (?, ?, ?)",
            (domain_name, status, details)
        )
        conn.commit()

# --- Telegram 通知 ---
class Notifier:
    """Telegram 通知器"""
    def __init__(self, token, chat_id):
        if not token or not chat_id:
            raise ValueError("Telegram token 和 chat_id 不能为空。")
        self.bot = Bot(token)
        self.chat_id = chat_id

    def send_notification(self, message):
        """发送通知"""
        try:
            self.bot.send_message(
                chat_id=self.chat_id,
                text=message,
                parse_mode=ParseMode.MARKDOWN
            )
            logging.info(f"成功发送 Telegram 通知。")
        except Exception as e:
            logging.error(f"发送 Telegram 通知失败: {e}")

# --- 域名检测 ---
class DomainChecker:
    """域名状态检测器"""
    def __init__(self, notifier):
        self.notifier = notifier

    def check_domain(self, domain_name):
        """
        检查单个域名的状态。
        如果域名可注册或即将到期，则发送通知。
        """
        logging.info(f"🔍 正在检测域名: {domain_name}")
        try:
            w = whois.whois(domain_name)
            
            if not w.domain_name:
                # 状态：可注册
                status = "✅ 可注册 (Available)"
                log_to_db(domain_name, status)
                self.notify_available(domain_name)
            else:
                # 状态：已注册
                exp_date = w.expiration_date
                if isinstance(exp_date, list):
                    exp_date = exp_date[0]
                
                if exp_date:
                    days_left = (exp_date - datetime.now()).days
                    status = f"🔴 已注册 (Registered) - 剩余 {days_left} 天到期"
                    details = f"注册商: {w.registrar}, 到期日: {exp_date.strftime('%Y-%m-%d')}"
                    log_to_db(domain_name, "Registered", details)
                    
                    # 到期提醒
                    if 0 < days_left <= 30:
                        self.notify_expiration(domain_name, days_left, exp_date)
                else:
                    status = "🔴 已注册 (Registered) - 到期日未知"
                    log_to_db(domain_name, "Registered", "到期日未知")

            console.print(f"  域名: [bold cyan]{domain_name}[/bold cyan] - 状态: {status}")

        except whois.parser.PywhoisError:
            # whois 查询失败，通常意味着域名可注册
            status = "✅ 可注册 (Available - whois error)"
            log_to_db(domain_name, status)
            self.notify_available(domain_name)
            console.print(f"  域名: [bold cyan]{domain_name}[/bold cyan] - 状态: {status}")
        except Exception as e:
            status = f"❌ 检测失败 (Error)"
            logging.error(f"检测域名 {domain_name} 时出错: {e}")
            log_to_db(domain_name, "Error", str(e))
            console.print(f"[red]  检测域名 {domain_name} 失败: {e}[/red]")

    def notify_available(self, domain_name):
        """当域名可注册时发送通知"""
        message = f"""
🚨 *紧急行动提醒：域名可注册！* 🚨

心仪的域名 **{domain_name}** 现在可以注册啦！

*检测信息*
- **域名:** `{domain_name}`
- **状态:** ✅ *可注册*
- **检测时间:** `{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}`

*推荐注册商*
- [NameSilo](https://www.namesilo.com/register.php?rid=3e13d39fy&search_type=new&domains={domain_name})
- [GoDaddy](https://www.godaddy.com/domains/searchresults.aspx?domainToCheck={domain_name})
- [Namecheap](https://www.namecheap.com/domains/registration/results.aspx?domain={domain_name})

*注册建议*
- **注册年限:** 建议首次注册多年以锁定优惠价格。
- **隐私保护:** 务必开启 WHOIS 隐私保护。
- **行动:** 好域名不等人，请立即行动！
        """
        self.notifier.send_notification(message)

    def notify_expiration(self, domain_name, days_left, exp_date):
        """当域名即将到期时发送通知"""
        message = f"""
⏰ *域名到期提醒* ⏰

您关注的域名 **{domain_name}** 即将到期！

*详细信息*
- **域名:** `{domain_name}`
- **状态:** ⏳ *即将到期*
- **剩余天数:** `{days_left}` 天
- **到期日期:** `{exp_date.strftime('%Y-%m-%d')}`

请及时续费或准备抢注！
        """
        self.notifier.send_notification(message)

def run_monitoring_task():
    """运行一次完整的监控任务"""
    console.rule(f"[bold blue]开始新一轮域名监控 @ {time.ctime()}", style="blue")
    
    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)

    try:
        token = config.get('telegram', 'token')
        chat_id = config.get('telegram', 'chat_id')
        domains_str = config.get('settings', 'domains_to_watch', fallback='')
        domains = [d.strip() for d in domains_str.split(',') if d.strip()]

        if not domains:
            logging.warning("配置文件中没有找到需要监控的域名。")
            return

        notifier = Notifier(token, chat_id)
        checker = DomainChecker(notifier)

        for domain in domains:
            checker.check_domain(domain)
            time.sleep(2) # 避免请求过于频繁

    except (configparser.NoSectionError, configparser.NoOptionError) as e:
        logging.error(f"配置文件 'config.ini' 格式错误或缺少必要项: {e}")
    except Exception as e:
        logging.critical(f"监控任务执行失败: {e}")

    console.rule("[bold blue]本轮监控结束", style="blue")


# --- 主程序入口 ---
if __name__ == "__main__":
    init_db()
    
    config = configparser.ConfigParser()
    config.read(CONFIG_FILE)
    interval = config.getint('settings', 'check_interval_minutes', fallback=60)
    
    console.print(f"[green]🚀 域名监控脚本启动成功！[/green]")
    console.print(f"   - 检测周期: [bold yellow]{interval}[/bold yellow] 分钟")
    console.print(f"   - 日志文件: [bold cyan]domain_monitor.log[/bold cyan]")
    console.print(f"   - 数据库:   [bold cyan]{DB_FILE}[/bold cyan]")
    
    # 立即执行一次，然后开始定时任务
    run_monitoring_task()
    
    schedule.every(interval).minutes.do(run_monitoring_task)

    while True:
        schedule.run_pending()
        time.sleep(1)
