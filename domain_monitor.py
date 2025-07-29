#!/usr/bin/env python3
"""
域名监控脚本 - 精简版
监控指定域名的注册状态，并通过 Telegram Bot 发送通知
"""

import whois
import requests
import json
import time
import logging
import os
import socket
from datetime import datetime
from typing import Dict

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/domain-monitor.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DomainMonitor:
    def __init__(self):
        """初始化域名监控器"""
        self.config_file = 'config.json'
        self.config = self.load_config()
        
    def load_config(self) -> Dict:
        """加载配置"""
        if os.path.exists(self.config_file):
            with open(self.config_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {
            'telegram_bot_token': '',
            'telegram_chat_id': '',
            'check_interval_minutes': 60,
            'domains': {}
        }
    
    def save_config(self):
        """保存配置"""
        with open(self.config_file, 'w', encoding='utf-8') as f:
            json.dump(self.config, f, ensure_ascii=False, indent=2)
        os.chmod(self.config_file, 0o600)
    
    def check_domain_availability(self, domain: str) -> Dict:
        """检查域名是否可注册"""
        result = {
            'domain': domain,
            'available': False,
            'expiry_date': None,
            'error': None
        }
        
        try:
            # DNS 查询
            try:
                socket.gethostbyname(domain)
                dns_exists = True
            except socket.gaierror:
                dns_exists = False
            
            # WHOIS 查询
            try:
                w = whois.whois(domain)
                if w.domain_name is None:
                    result['available'] = True
                else:
                    result['available'] = False
                    result['expiry_date'] = str(w.expiration_date) if w.expiration_date else None
            except:
                result['available'] = not dns_exists
                
        except Exception as e:
            result['error'] = str(e)
            logger.error(f"检查域名 {domain} 时出错: {e}")
            
        return result
    
    def send_telegram_notification(self, message: str):
        """发送 Telegram 通知"""
        if not self.config['telegram_bot_token'] or not self.config['telegram_chat_id']:
            logger.error("Telegram 未配置")
            return
            
        url = f"https://api.telegram.org/bot{self.config['telegram_bot_token']}/sendMessage"
        data = {
            'chat_id': self.config['telegram_chat_id'],
            'text': message,
            'parse_mode': 'HTML'
        }
        
        try:
            response = requests.post(url, data=data)
            if response.status_code == 200:
                logger.info("通知发送成功")
            else:
                logger.error(f"通知发送失败: {response.text}")
        except Exception as e:
            logger.error(f"发送通知时出错: {e}")
    
    def format_notification(self, domain: str, status: Dict) -> str:
        """格式化通知消息"""
        if status['available']:
            return f"""🎯 <b>域名可注册通知</b>

📌 域名：<code>{domain}</code>
✅ 状态：可以注册！
⏰ 时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}

⚡ 请尽快注册，以免被他人抢注！

推荐注册商：
• Namecheap
• Cloudflare
• 阿里云"""
        else:
            return f"""📊 <b>域名状态</b>

📌 域名：<code>{domain}</code>
❌ 状态：已被注册
⏰ 时间：{datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"""
    
    def check_all_domains(self):
        """检查所有域名"""
        domains = self.config.get('domains', {})
        if not domains:
            logger.info("没有要监控的域名")
            return
            
        logger.info(f"开始检查 {len(domains)} 个域名...")
        
        for domain, info in domains.items():
            logger.info(f"检查域名: {domain}")
            status = self.check_domain_availability(domain)
            
            # 更新状态
            info['last_checked'] = datetime.now().isoformat()
            info['status'] = 'available' if status['available'] else 'registered'
            
            # 发送通知
            if status['available'] and not info.get('notified'):
                message = self.format_notification(domain, status)
                self.send_telegram_notification(message)
                info['notified'] = True
            elif not status['available'] and info.get('notified'):
                info['notified'] = False
            
            time.sleep(2)
        
        self.save_config()
        logger.info("检查完成")
    
    def run(self):
        """运行监控"""
        interval = self.config.get('check_interval_minutes', 60)
        logger.info(f"域名监控服务启动，检查间隔: {interval} 分钟")
        
        # 启动通知
        self.send_telegram_notification(
            f"🚀 <b>域名监控服务已启动</b>\n\n"
            f"监控域名数: {len(self.config.get('domains', {}))}\n"
            f"检查间隔: {interval} 分钟"
        )
        
        while True:
            self.check_all_domains()
            time.sleep(interval * 60)

if __name__ == '__main__':
    monitor = DomainMonitor()
    monitor.run()
