#!/usr/bin/env python3
"""
域名监控脚本
监控指定域名的注册状态，并通过 Telegram Bot 发送通知
"""

import whois
import requests
import json
import time
import logging
from datetime import datetime, timedelta
import schedule
import os
from typing import List, Dict, Optional
import socket
import subprocess

# 配置日志
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('domain_monitor.log'),
        logging.StreamHandler()
    ]
)
logger = logging.getLogger(__name__)

class DomainMonitor:
    def __init__(self, telegram_bot_token: str, telegram_chat_id: str):
        """
        初始化域名监控器
        
        :param telegram_bot_token: Telegram Bot Token
        :param telegram_chat_id: Telegram Chat ID
        """
        self.bot_token = telegram_bot_token
        self.chat_id = telegram_chat_id
        self.domains_file = 'domains.json'
        self.domains = self.load_domains()
        
    def load_domains(self) -> Dict[str, Dict]:
        """加载要监控的域名列表"""
        if os.path.exists(self.domains_file):
            with open(self.domains_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        return {}
    
    def save_domains(self):
        """保存域名列表"""
        with open(self.domains_file, 'w', encoding='utf-8') as f:
            json.dump(self.domains, f, ensure_ascii=False, indent=2)
    
    def add_domain(self, domain: str, notes: str = ""):
        """添加要监控的域名"""
        self.domains[domain] = {
            'added_at': datetime.now().isoformat(),
            'last_checked': None,
            'status': 'unknown',
            'notes': notes,
            'notification_sent': False
        }
        self.save_domains()
        logger.info(f"已添加域名监控: {domain}")
        
    def remove_domain(self, domain: str):
        """移除监控的域名"""
        if domain in self.domains:
            del self.domains[domain]
            self.save_domains()
            logger.info(f"已移除域名监控: {domain}")
    
    def check_domain_availability(self, domain: str) -> Dict:
        """
        检查域名是否可注册
        
        返回域名状态信息
        """
        result = {
            'domain': domain,
            'available': False,
            'expiry_date': None,
            'registrar': None,
            'dns_servers': None,
            'error': None,
            'check_time': datetime.now().isoformat()
        }
        
        try:
            # 首先尝试 DNS 查询
            try:
                socket.gethostbyname(domain)
                dns_exists = True
            except socket.gaierror:
                dns_exists = False
            
            # 尝试使用 whois 查询
            try:
                w = whois.whois(domain)
                
                if w.domain_name is None:
                    result['available'] = True
                else:
                    result['available'] = False
                    result['expiry_date'] = str(w.expiration_date) if w.expiration_date else None
                    result['registrar'] = w.registrar
                    result['dns_servers'] = w.name_servers
                    
            except Exception as whois_error:
                # 如果 whois 查询失败，使用 DNS 结果
                if not dns_exists:
                    result['available'] = True
                else:
                    result['available'] = False
                    result['error'] = f"WHOIS查询失败，但DNS记录存在"
                    
        except Exception as e:
            result['error'] = str(e)
            logger.error(f"检查域名 {domain} 时出错: {e}")
            
        return result
    
    def send_telegram_notification(self, message: str, parse_mode: str = 'HTML'):
        """发送 Telegram 通知"""
        url = f'https://api.telegram.org/bot{self.bot_token}/sendMessage'
        
        data = {
            'chat_id': self.chat_id,
            'text': message,
            'parse_mode': parse_mode
        }
        
        try:
            response = requests.post(url, data=data)
            if response.status_code == 200:
                logger.info("Telegram 通知发送成功")
            else:
                logger.error(f"Telegram 通知发送失败: {response.text}")
        except Exception as e:
            logger.error(f"发送 Telegram 通知时出错: {e}")
    
    def format_notification_message(self, domain: str, status: Dict) -> str:
        """格式化通知消息"""
        current_time = datetime.now().strftime('%Y-%m-%d %H:%M:%S')
        
        if status['available']:
            message = f"""🎯 <b>域名可注册通知</b> 🎯

📌 <b>域名：</b><code>{domain}</code>
✅ <b>状态：</b>可以注册！
⏰ <b>检测时间：</b>{current_time}

<b>⚡ 立即行动！</b>
请尽快前往域名注册商注册此域名，以免被他人抢注。

<b>推荐注册商：</b>
• Namecheap: https://www.namecheap.com
• GoDaddy: https://www.godaddy.com
• Cloudflare: https://www.cloudflare.com/products/registrar/
• 阿里云: https://wanwang.aliyun.com
• 腾讯云: https://dnspod.cloud.tencent.com

<b>注册建议：</b>
1. 建议一次性注册多年，避免忘记续费
2. 开启域名隐私保护
3. 设置自动续费
4. 使用可靠的DNS服务商

#{domain.replace('.', '_')} #域名可注册"""
            
        else:
            # 域名已被注册的情况
            expiry_info = ""
            if status.get('expiry_date'):
                try:
                    expiry_date = datetime.fromisoformat(status['expiry_date'].replace('Z', '+00:00'))
                    days_until_expiry = (expiry_date - datetime.now()).days
                    expiry_info = f"""
📅 <b>到期时间：</b>{expiry_date.strftime('%Y-%m-%d')}
⏳ <b>距离到期：</b>{days_until_expiry} 天"""
                    
                    if days_until_expiry <= 30:
                        expiry_info += "\n⚠️ <b>注意：</b>域名即将到期，请密切关注！"
                except:
                    pass
            
            message = f"""📊 <b>域名状态更新</b> 📊

📌 <b>域名：</b><code>{domain}</code>
❌ <b>状态：</b>已被注册
⏰ <b>检测时间：</b>{current_time}
🏢 <b>注册商：</b>{status.get('registrar', '未知')}{expiry_info}

<b>后续建议：</b>
• 继续监控此域名
• 考虑其他后缀（.com/.net/.org等）
• 尝试添加前缀或后缀

#{domain.replace('.', '_')} #域名已注册"""
        
        # 添加备注信息
        if domain in self.domains and self.domains[domain].get('notes'):
            message += f"\n\n📝 <b>备注：</b>{self.domains[domain]['notes']}"
            
        return message
    
    def check_all_domains(self):
        """检查所有监控的域名"""
        logger.info(f"开始检查 {len(self.domains)} 个域名...")
        
        for domain in list(self.domains.keys()):
            logger.info(f"正在检查域名: {domain}")
            
            status = self.check_domain_availability(domain)
            
            # 更新域名状态
            self.domains[domain]['last_checked'] = datetime.now().isoformat()
            self.domains[domain]['status'] = 'available' if status['available'] else 'registered'
            
            # 发送通知的条件
            should_notify = False
            
            if status['available'] and not self.domains[domain].get('notification_sent'):
                # 域名可用且未发送过通知
                should_notify = True
                self.domains[domain]['notification_sent'] = True
                
            elif not status['available'] and self.domains[domain].get('notification_sent'):
                # 域名从可用变为不可用，重置通知状态
                self.domains[domain]['notification_sent'] = False
                
            elif status.get('expiry_date'):
                # 检查是否即将到期
                try:
                    expiry_date = datetime.fromisoformat(status['expiry_date'].replace('Z', '+00:00'))
                    days_until_expiry = (expiry_date - datetime.now()).days
                    if days_until_expiry <= 7 and not self.domains[domain].get('expiry_notification_sent'):
                        should_notify = True
                        self.domains[domain]['expiry_notification_sent'] = True
                except:
                    pass
            
            if should_notify:
                message = self.format_notification_message(domain, status)
                self.send_telegram_notification(message)
            
            self.save_domains()
            
            # 避免请求过快
            time.sleep(2)
        
        logger.info("域名检查完成")
    
    def run_scheduled_checks(self, check_interval_minutes: int = 60):
        """运行定时检查"""
        logger.info(f"启动域名监控服务，检查间隔: {check_interval_minutes} 分钟")
        
        # 立即执行一次检查
        self.check_all_domains()
        
        # 设置定时任务
        schedule.every(check_interval_minutes).minutes.do(self.check_all_domains)
        
        # 发送启动通知
        self.send_telegram_notification(
            f"🚀 <b>域名监控服务已启动</b>\n\n"
            f"监控域名数量: {len(self.domains)}\n"
            f"检查间隔: {check_interval_minutes} 分钟\n"
            f"当前时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
        )
        
        while True:
            schedule.run_pending()
            time.sleep(1)


def main():
    """主函数"""
    # 从环境变量读取配置
    bot_token = os.getenv('TELEGRAM_BOT_TOKEN')
    chat_id = os.getenv('TELEGRAM_CHAT_ID')
    check_interval = int(os.getenv('CHECK_INTERVAL_MINUTES', '60'))
    
    if not bot_token or not chat_id:
        logger.error("请设置环境变量 TELEGRAM_BOT_TOKEN 和 TELEGRAM_CHAT_ID")
        return
    
    # 创建监控器实例
    monitor = DomainMonitor(bot_token, chat_id)
    
    # 从命令行参数添加域名
    import sys
    if len(sys.argv) > 1:
        for domain in sys.argv[1:]:
            if '.' in domain:  # 简单验证是否为域名格式
                monitor.add_domain(domain)
    
    # 如果没有要监控的域名，添加示例
    if not monitor.domains:
        logger.warning("没有要监控的域名，请添加域名到 domains.json 文件")
        # 示例域名
        monitor.add_domain('example-domain-12345.com', '示例域名')
    
    # 开始监控
    try:
        monitor.run_scheduled_checks(check_interval)
    except KeyboardInterrupt:
        logger.info("域名监控服务已停止")
    except Exception as e:
        logger.error(f"运行出错: {e}")
        monitor.send_telegram_notification(f"❌ 域名监控服务出错: {str(e)}")


if __name__ == '__main__':
    main()
