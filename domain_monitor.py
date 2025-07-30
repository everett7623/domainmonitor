#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
DomainMonitor - 域名状态监控系统主程序

作者: everett7623
GitHub: https://github.com/everett7623/domainmonitor
版本: v1.0.0

功能特点:
- 🔍 自动检测域名注册状态
- 📱 通过 Telegram Bot 发送详细通知
- 📊 记录域名检查历史
- ⏰ 域名到期提醒
- 📝 详细日志记录
"""

import os
import sys
import json
import time
import socket
import logging
import subprocess
import threading
from datetime import datetime, timedelta
from typing import Dict, List, Optional, Tuple
import requests
import whois
from pathlib import Path

# 配置路径
BASE_DIR = Path(__file__).parent
CONFIG_FILE = BASE_DIR / "config" / "config.json"
DATA_DIR = BASE_DIR / "data"
LOG_DIR = BASE_DIR / "logs"

# 创建必要的目录
DATA_DIR.mkdir(exist_ok=True)
LOG_DIR.mkdir(exist_ok=True)

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler(LOG_DIR / "domainmonitor.log"),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger("DomainMonitor")


class DomainMonitor:
    """域名监控主类"""
    
    def __init__(self):
        self.config = self.load_config()
        self.telegram_bot = TelegramBot(
            self.config["telegram"]["bot_token"],
            self.config["telegram"]["chat_id"]
        )
        self.domain_history = self.load_history()
        self.check_interval = self.config.get("check_interval", 300)
        
    def load_config(self) -> dict:
        """加载配置文件"""
        try:
            with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"加载配置文件失败: {e}")
            sys.exit(1)
            
    def save_config(self):
        """保存配置文件"""
        try:
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                json.dump(self.config, f, indent=4, ensure_ascii=False)
        except Exception as e:
            logger.error(f"保存配置文件失败: {e}")
            
    def load_history(self) -> dict:
        """加载历史记录"""
        history_file = DATA_DIR / "history.json"
        if history_file.exists():
            try:
                with open(history_file, 'r', encoding='utf-8') as f:
                    return json.load(f)
            except:
                return {}
        return {}
        
    def save_history(self):
        """保存历史记录"""
        history_file = DATA_DIR / "history.json"
        try:
            with open(history_file, 'w', encoding='utf-8') as f:
                json.dump(self.domain_history, f, indent=4, ensure_ascii=False)
        except Exception as e:
            logger.error(f"保存历史记录失败: {e}")
            
    def check_domain_status(self, domain: str) -> Tuple[str, Optional[dict]]:
        """
        检查域名状态
        返回: (状态, 详细信息)
        状态: available, registered, error
        """
        try:
            # 使用 whois 查询
            w = whois.whois(domain)
            
            # 判断域名是否已注册
            if w.domain_name:
                # 获取到期时间
                expiry_date = None
                if w.expiration_date:
                    if isinstance(w.expiration_date, list):
                        expiry_date = w.expiration_date[0]
                    else:
                        expiry_date = w.expiration_date
                        
                return "registered", {
                    "registrar": w.registrar,
                    "creation_date": str(w.creation_date) if w.creation_date else None,
                    "expiration_date": str(expiry_date) if expiry_date else None,
                    "name_servers": w.name_servers if w.name_servers else []
                }
            else:
                return "available", None
                
        except whois.parser.PywhoisError:
            # 域名未注册
            return "available", None
        except Exception as e:
            logger.error(f"检查域名 {domain} 时出错: {e}")
            return "error", {"error": str(e)}
            
    def check_all_domains(self):
        """检查所有域名"""
        logger.info("开始检查所有域名...")
        
        for domain in self.config.get("domains", []):
            try:
                status, info = self.check_domain_status(domain)
                current_time = datetime.now().isoformat()
                
                # 初始化域名历史记录
                if domain not in self.domain_history:
                    self.domain_history[domain] = {
                        "first_check": current_time,
                        "last_check": current_time,
                        "status_history": [],
                        "last_status": None
                    }
                
                # 更新历史记录
                history = self.domain_history[domain]
                history["last_check"] = current_time
                
                # 添加状态变化记录
                if history["last_status"] != status:
                    history["status_history"].append({
                        "time": current_time,
                        "status": status,
                        "info": info
                    })
                    
                    # 发送通知
                    if status == "available" and history["last_status"] == "registered":
                        self.send_available_notification(domain)
                    elif status == "registered" and info and info.get("expiration_date"):
                        # 检查是否即将到期
                        self.check_expiration(domain, info["expiration_date"])
                        
                history["last_status"] = status
                
                logger.info(f"域名 {domain} 状态: {status}")
                
            except Exception as e:
                logger.error(f"检查域名 {domain} 失败: {e}")
                
        self.save_history()
        
    def check_expiration(self, domain: str, expiration_date: str):
        """检查域名是否即将到期"""
        try:
            # 解析到期时间
            if isinstance(expiration_date, str):
                # 尝试多种日期格式
                for fmt in ["%Y-%m-%d %H:%M:%S", "%Y-%m-%d", "%Y-%m-%dT%H:%M:%S"]:
                    try:
                        expiry = datetime.strptime(expiration_date.split('.')[0], fmt)
                        break
                    except:
                        continue
                else:
                    return
            else:
                expiry = expiration_date
                
            # 计算剩余天数
            days_left = (expiry - datetime.now()).days
            
            # 30天内到期提醒
            if days_left <= 30 and days_left > 0:
                self.send_expiration_warning(domain, days_left)
                
        except Exception as e:
            logger.error(f"检查域名 {domain} 到期时间失败: {e}")
            
    def send_available_notification(self, domain: str):
        """发送域名可注册通知"""
        message = f"""
🎉 <b>域名可以注册啦！</b> 🎉

📌 <b>域名:</b> <code>{domain}</code>
⏰ <b>检测时间:</b> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
🔥 <b>状态:</b> <b>可注册</b>

📋 <b>推荐注册商:</b>
"""
        
        # 添加注册商信息
        for registrar in self.config.get("registrars", []):
            message += f"\n▫️ <b>{registrar['name']}</b>"
            message += f"\n  🔗 {registrar['url']}"
            if registrar.get("features"):
                message += f"\n  ✨ {', '.join(registrar['features'])}"
            message += "\n"
            
        message += """
💡 <b>注册建议:</b>
• 建议注册 3-5 年，价格更优惠
• 开启域名隐私保护
• 设置自动续费避免过期
• 立即注册，好域名稍纵即逝！

⚡ <b>紧急行动:</b> 请立即前往注册商抢注！
"""
        
        self.telegram_bot.send_message(message)
        logger.info(f"已发送域名 {domain} 可注册通知")
        
    def send_expiration_warning(self, domain: str, days_left: int):
        """发送域名到期提醒"""
        urgency = "🟡" if days_left > 7 else "🔴"
        
        message = f"""
{urgency} <b>域名到期提醒</b> {urgency}

📌 <b>域名:</b> <code>{domain}</code>
⏳ <b>剩余天数:</b> <b>{days_left} 天</b>
📅 <b>检查时间:</b> {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

⚠️ <b>请及时续费，避免域名过期！</b>
"""
        
        # 只在特定天数发送提醒
        if days_left in [30, 14, 7, 3, 1]:
            self.telegram_bot.send_message(message)
            logger.info(f"已发送域名 {domain} 到期提醒 (剩余 {days_left} 天)")
            
    def run(self):
        """运行监控服务"""
        logger.info("DomainMonitor 服务已启动")
        self.telegram_bot.send_message(
            "🚀 <b>DomainMonitor 服务已启动</b>\n\n"
            f"📊 监控域名数: {len(self.config.get('domains', []))}\n"
            f"⏱️ 检查间隔: {self.check_interval} 秒"
        )
        
        while True:
            try:
                self.check_all_domains()
                time.sleep(self.check_interval)
            except KeyboardInterrupt:
                logger.info("收到停止信号，正在关闭...")
                break
            except Exception as e:
                logger.error(f"运行时错误: {e}")
                time.sleep(60)  # 出错后等待1分钟再继续


class TelegramBot:
    """Telegram Bot 通知类"""
    
    def __init__(self, bot_token: str, chat_id: str):
        self.bot_token = bot_token
        self.chat_id = chat_id
        self.api_url = f"https://api.telegram.org/bot{bot_token}"
        
    def send_message(self, message: str):
        """发送 Telegram 消息"""
        try:
            url = f"{self.api_url}/sendMessage"
            data = {
                "chat_id": self.chat_id,
                "text": message,
                "parse_mode": "HTML",
                "disable_web_page_preview": True
            }
            
            response = requests.post(url, json=data, timeout=10)
            
            if response.status_code == 200:
                logger.debug("Telegram 消息发送成功")
            else:
                logger.error(f"Telegram 消息发送失败: {response.text}")
                
        except Exception as e:
            logger.error(f"发送 Telegram 消息失败: {e}")


def main():
    """主函数"""
    try:
        # 检查配置文件
        if not CONFIG_FILE.exists():
            logger.error("配置文件不存在，请先运行安装脚本")
            sys.exit(1)
            
        # 创建并运行监控器
        monitor = DomainMonitor()
        monitor.run()
        
    except Exception as e:
        logger.error(f"程序启动失败: {e}")
        sys.exit(1)


if __name__ == "__main__":
    main()
