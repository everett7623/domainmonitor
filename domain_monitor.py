#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
域名监控系统核心程序
作者: everett7623
功能: 自动监控域名注册状态并通过 Telegram 发送通知
"""

import os
import sys
import json
import time
import whois
import logging
import schedule
import requests
import threading
import dns.resolver
from datetime import datetime, timedelta
from telegram import Bot
from telegram.error import TelegramError
from logging.handlers import RotatingFileHandler

# 版本信息
VERSION = "1.0.0"
AUTHOR = "everett7623"

# 配置文件路径
CONFIG_FILE = "/opt/domainmonitor/config.json"
LOG_DIR = "/opt/domainmonitor/logs"
DATA_DIR = "/opt/domainmonitor/data"

# 确保目录存在
os.makedirs(LOG_DIR, exist_ok=True)
os.makedirs(DATA_DIR, exist_ok=True)

# 配置日志
def setup_logging():
    """配置日志系统"""
    logger = logging.getLogger('DomainMonitor')
    logger.setLevel(logging.INFO)
    
    # 文件处理器（自动轮转）
    file_handler = RotatingFileHandler(
        os.path.join(LOG_DIR, 'monitor.log'),
        maxBytes=10*1024*1024,  # 10MB
        backupCount=5
    )
    file_handler.setLevel(logging.INFO)
    
    # 控制台处理器
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(logging.INFO)
    
    # 格式化器
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    file_handler.setFormatter(formatter)
    console_handler.setFormatter(formatter)
    
    logger.addHandler(file_handler)
    logger.addHandler(console_handler)
    
    return logger

logger = setup_logging()

class DomainMonitor:
    """域名监控类"""
    
    def __init__(self):
        self.config = self.load_config()
        self.bot = Bot(token=self.config['telegram']['bot_token'])
        self.chat_id = self.config['telegram']['chat_id']
        self.domains = self.config.get('domains', [])
        self.check_interval = self.config.get('check_interval', 3600)
        self.history_file = os.path.join(DATA_DIR, 'history.json')
        self.history = self.load_history()
        
    def load_config(self):
        """加载配置文件"""
        try:
            with open(CONFIG_FILE, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"加载配置文件失败: {e}")
            sys.exit(1)
    
    def save_config(self):
        """保存配置文件"""
        try:
            with open(CONFIG_FILE, 'w') as f:
                json.dump(self.config, f, indent=4)
        except Exception as e:
            logger.error(f"保存配置文件失败: {e}")
    
    def load_history(self):
        """加载历史记录"""
        if os.path.exists(self.history_file):
            try:
                with open(self.history_file, 'r') as f:
                    return json.load(f)
            except:
                return {}
        return {}
    
    def save_history(self):
        """保存历史记录"""
        try:
            with open(self.history_file, 'w') as f:
                json.dump(self.history, f, indent=4)
        except Exception as e:
            logger.error(f"保存历史记录失败: {e}")
    
    def check_domain_whois(self, domain):
        """通过 WHOIS 检查域名状态"""
        try:
            w = whois.whois(domain)
            
            # 检查域名是否已注册
            if w.domain_name:
                # 获取过期时间
                expiry_date = None
                if isinstance(w.expiration_date, list):
                    expiry_date = w.expiration_date[0]
                else:
                    expiry_date = w.expiration_date
                
                if expiry_date:
                    days_until_expiry = (expiry_date - datetime.now()).days
                    return {
                        'status': 'registered',
                        'registrar': w.registrar,
                        'creation_date': str(w.creation_date),
                        'expiration_date': str(expiry_date),
                        'days_until_expiry': days_until_expiry,
                        'nameservers': w.name_servers
                    }
                else:
                    return {
                        'status': 'registered',
                        'registrar': w.registrar,
                        'info': 'Unable to get expiration date'
                    }
            else:
                return {'status': 'available'}
                
        except Exception as e:
            logger.debug(f"WHOIS 查询失败 {domain}: {e}")
            return {'status': 'unknown', 'error': str(e)}
    
    def check_domain_dns(self, domain):
        """通过 DNS 查询检查域名"""
        try:
            resolver = dns.resolver.Resolver()
            resolver.timeout = 5
            resolver.lifetime = 5
            
            # 尝试解析 A 记录
            answers = resolver.resolve(domain, 'A')
            if answers:
                return True
        except:
            pass
        
        return False
    
    def check_domain(self, domain):
        """综合检查域名状态"""
        logger.info(f"正在检查域名: {domain}")
        
        # 首先通过 WHOIS 查询
        whois_result = self.check_domain_whois(domain)
        
        # 如果 WHOIS 无法确定，尝试 DNS 查询
        if whois_result['status'] == 'unknown':
            dns_exists = self.check_domain_dns(domain)
            if dns_exists:
                whois_result['status'] = 'registered'
                whois_result['info'] = 'Confirmed via DNS'
        
        # 记录检查历史
        if domain not in self.history:
            self.history[domain] = []
        
        self.history[domain].append({
            'timestamp': datetime.now().isoformat(),
            'status': whois_result['status'],
            'details': whois_result
        })
        
        # 只保留最近30条记录
        self.history[domain] = self.history[domain][-30:]
        self.save_history()
        
        return whois_result
    
    def format_message(self, domain, status_info, previous_status=None):
        """格式化通知消息"""
        emoji_map = {
            'available': '✅',
            'registered': '❌',
            'unknown': '❓',
            'expiring_soon': '⚠️',
            'expired': '🎉'
        }
        
        status = status_info['status']
        emoji = emoji_map.get(status, '📌')
        
        message = f"{emoji} <b>域名监控通知</b>\n\n"
        message += f"📍 域名: <code>{domain}</code>\n"
        message += f"📊 状态: <b>{status.upper()}</b>\n"
        message += f"🕐 时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
        
        if status == 'available':
            message += f"\n🎉 <b>好消息！域名现在可以注册！</b>\n"
            message += f"🚀 请尽快前往注册商抢注\n"
            
        elif status == 'registered':
            if 'registrar' in status_info:
                message += f"🏢 注册商: {status_info['registrar']}\n"
            
            if 'days_until_expiry' in status_info:
                days = status_info['days_until_expiry']
                message += f"📅 到期时间: {status_info['expiration_date']}\n"
                message += f"⏳ 剩余天数: {days} 天\n"
                
                if days <= 30:
                    message += f"\n⚠️ <b>域名即将到期！</b>\n"
                    message += f"💡 建议关注该域名的续费状态\n"
        
        elif status == 'unknown':
            message += f"❗ 错误信息: {status_info.get('error', '未知错误')}\n"
            message += f"💡 可能是网络问题，稍后会重试\n"
        
        # 如果状态发生变化
        if previous_status and previous_status != status:
            message += f"\n🔄 <b>状态变更</b>\n"
            message += f"之前: {previous_status} → 现在: {status}\n"
        
        return message
    
    def send_notification(self, message):
        """发送 Telegram 通知"""
        try:
            self.bot.send_message(
                chat_id=self.chat_id,
                text=message,
                parse_mode='HTML'
            )
            logger.info("通知发送成功")
        except TelegramError as e:
            logger.error(f"发送通知失败: {e}")
    
    def check_all_domains(self):
        """检查所有域名"""
        logger.info(f"开始检查 {len(self.domains)} 个域名")
        
        for domain in self.domains:
            try:
                # 获取上次状态
                previous_status = None
                if domain in self.history and self.history[domain]:
                    previous_status = self.history[domain][-1]['status']
                
                # 检查当前状态
                current_status = self.check_domain(domain)
                
                # 判断是否需要通知
                should_notify = False
                
                # 状态变化时通知
                if previous_status != current_status['status']:
                    should_notify = True
                
                # 域名可用时始终通知
                if current_status['status'] == 'available':
                    should_notify = True
                
                # 即将到期时通知（30天内）
                if (current_status['status'] == 'registered' and 
                    'days_until_expiry' in current_status and 
                    current_status['days_until_expiry'] <= 30):
                    # 每天只通知一次
                    last_check = datetime.fromisoformat(self.history[domain][-2]['timestamp']) if len(self.history[domain]) > 1 else None
                    if not last_check or (datetime.now() - last_check).days >= 1:
                        should_notify = True
                
                # 发送通知
                if should_notify:
                    message = self.format_message(domain, current_status, previous_status)
                    self.send_notification(message)
                
                # 延迟一下，避免请求过快
                time.sleep(2)
                
            except Exception as e:
                logger.error(f"检查域名 {domain} 时出错: {e}")
        
        logger.info("域名检查完成")
    
    def send_daily_report(self):
        """发送每日报告"""
        message = "📊 <b>每日域名监控报告</b>\n\n"
        message += f"📅 日期: {datetime.now().strftime('%Y-%m-%d')}\n"
        message += f"🔍 监控域名数: {len(self.domains)}\n\n"
        
        available_count = 0
        expiring_soon = []
        
        for domain in self.domains:
            if domain in self.history and self.history[domain]:
                last_status = self.history[domain][-1]
                if last_status['status'] == 'available':
                    available_count += 1
                elif (last_status['status'] == 'registered' and 
                      'days_until_expiry' in last_status['details'] and 
                      last_status['details']['days_until_expiry'] <= 30):
                    expiring_soon.append((domain, last_status['details']['days_until_expiry']))
        
        message += f"✅ 可注册域名: {available_count} 个\n"
        
        if expiring_soon:
            message += f"\n⚠️ <b>即将到期域名:</b>\n"
            for domain, days in sorted(expiring_soon, key=lambda x: x[1]):
                message += f"• {domain} ({days} 天)\n"
        
        message += f"\n💡 使用 /status 查看详细状态"
        
        self.send_notification(message)
    
    def run(self):
        """运行监控服务"""
        logger.info(f"域名监控服务启动 v{VERSION}")
        logger.info(f"监控域名数: {len(self.domains)}")
        logger.info(f"检查间隔: {self.check_interval} 秒")
        
        # 立即执行一次检查
        self.check_all_domains()
        
        # 设置定时任务
        schedule.every(self.check_interval).seconds.do(self.check_all_domains)
        schedule.every().day.at("09:00").do(self.send_daily_report)
        
        # 发送启动通知
        self.send_notification(
            f"🚀 域名监控服务已启动\n"
            f"📊 监控域名: {len(self.domains)} 个\n"
            f"⏰ 检查间隔: {self.check_interval//60} 分钟"
        )
        
        # 运行调度器
        while True:
            try:
                schedule.run_pending()
                time.sleep(1)
            except KeyboardInterrupt:
                logger.info("收到停止信号，正在关闭...")
                break
            except Exception as e:
                logger.error(f"运行时错误: {e}")
                time.sleep(60)

def main():
    """主函数"""
    try:
        monitor = DomainMonitor()
        monitor.run()
    except Exception as e:
        logger.error(f"启动失败: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
