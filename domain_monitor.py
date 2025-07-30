#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
域名监控系统主程序
支持自动检测域名注册状态并通过Telegram Bot发送通知
作者: everett7623
版本: 2.0.0
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
                'notify_days_before_expiry': [30, 7, 3, 1]
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
            
        # 方法3: 使用curl命令
        try:
            cmd = [
                'curl', '-s', '-X', 'POST',
                f'https://api.telegram.org/bot{bot_token}/sendMessage',
                '-d', f'chat_id={chat_id}',
                '-d', f'text={message}',
                '-d', 'parse_mode=HTML',
                '-d', 'disable_web_page_preview=true'
            ]
            
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                logging.info("Telegram通知发送成功 (使用curl)")
                return True
            else:
                logging.error(f"curl发送失败: {result.stderr}")
                
        except Exception as e:
            logging.error(f"curl命令执行失败: {e}")
            
        return False
        
    def check_domain_whois(self, domain: str) -> Tuple[str, Optional[datetime], Optional[int]]:
        """使用whois命令检查域名状态"""
        try:
            # 执行whois命令
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
                'no entries found', 'status: free', 'not exist',
                'no matching record', 'domain status: available'
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
            'registry expiry date:', 'registrar registration expiration date:',
            'paid-till:', 'valid until:', 'renewal date:'
        ]
        
        lines = whois_text.split('\n')
        for line in lines:
            line_lower = line.lower()
            for keyword in expiry_keywords:
                if keyword in line_lower:
                    # 提取日期部分
                    date_str = line.split(':', 1)[1].strip()
                    
                    # 尝试多种日期格式
                    date_formats = [
                        '%Y-%m-%d', '%d-%m-%Y', '%Y/%m/%d', '%d/%m/%Y',
                        '%Y.%m.%d', '%d.%m.%Y', '%Y-%m-%dT%H:%M:%SZ',
                        '%Y-%m-%dT%H:%M:%S%z', '%Y-%m-%d %H:%M:%S',
                        '%d-%b-%Y', '%d %b %Y', '%Y%m%d'
                    ]
                    
                    for fmt in date_formats:
                        try:
                            # 处理可能包含的额外信息
                            clean_date = date_str.split()[0]
                            return datetime.strptime(clean_date, fmt)
                        except:
                            continue
                            
                    # 尝试处理特殊格式
                    try:
                        # 处理类似 "2025-01-29T00:00:00Z" 的格式
                        if 'T' in date_str:
                            clean_date = date_str.split('.')[0].replace('Z', '')
                            return datetime.strptime(clean_date, '%Y-%m-%dT%H:%M:%S')
                    except:
                        pass
                        
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
            message += f"• <a href='https://porkbun.com/checkout/search?q={domain}'>Porkbun</a> - 性价比高\n"
            message += f"• <a href='https://www.namesilo.com/domain/search-domains?query={domain}'>NameSilo</a> - 价格便宜\n\n"
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
                        message += f"\n⚠️ <b>域名已过期，可能即将释放！</b>\n"
                        message += f"建议增加检查频率，密切关注释放时间。"
                    elif days_until_expiry == 0:
                        message += f"<b>状态:</b> 🔥 <b>今天过期！</b>\n"
                        message += f"\n⚠️ <b>密切关注，可能随时释放！</b>"
                    elif days_until_expiry == 1:
                        message += f"<b>剩余天数:</b> 🔥 <b>仅剩 1 天！明天过期！</b>\n"
                        message += f"\n⚠️ <b>域名即将过期，请做好抢注准备！</b>"
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
            try:
                last_notified_time = datetime.fromisoformat(last_notified)
                if (datetime.now() - last_notified_time).total_seconds() > 86400:
                    return True, "定期提醒(24小时)"
            except:
                pass
                
        # 域名已过期
        if status == 'registered' and days_until_expiry is not None and days_until_expiry < 0:
            if last_status != 'expired':
                return True, "域名已过期"
                
        # 即将过期提醒
        if status == 'registered' and days_until_expiry is not None:
            notify_days = self.config.get('notify_days_before_expiry', [30, 7, 3, 1])
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
        errors = 0
        
        for domain in domains:
            logging.info(f"正在检查域名: {domain}")
            
            try:
                status, expiry_date, days_until_expiry = self.check_domain_whois(domain)
                
                if status == 'available':
                    available += 1
                elif status == 'error':
                    errors += 1
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
                            for days in self.config.get('notify_days_before_expiry', [30, 7, 3, 1]):
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
                    for days in [30, 7, 3, 1]:
                        self.history[domain].pop(f'notified_{days}d', None)
                
            except Exception as e:
                logging.error(f"检查域名 {domain} 时发生错误: {e}")
                errors += 1
                
            # 避免请求过快
            time.sleep(2)
            
        self.save_history()
        
        # 发送检查摘要（仅在有重要信息时）
        if available > 0 or expiring > 0 or errors > 0:
            summary = f"<b>📊 域名检查完成</b>\n\n"
            summary += f"检查域名: {checked} 个\n"
            
            if available > 0:
                summary += f"✅ 可注册: {available} 个\n"
            if expiring > 0:
                summary += f"⚠️ 即将过期: {expiring} 个\n"
            if errors > 0:
                summary += f"❌ 检查失败: {errors} 个\n"
                
            summary += f"\n时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}"
            
            self.send_telegram_notification(summary)
            
        logging.info(f"域名检查完成 - 检查: {checked}, 可注册: {available}, 即将过期: {expiring}, 错误: {errors}")
        
    def test_notification(self):
        """测试通知功能"""
        test_message = (
            "<b>🔔 域名监控系统测试</b>\n\n"
            "✅ Telegram通知配置成功！\n"
            f"🕐 当前时间: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n"
            f"⏰ 检查间隔: {self.config.get('check_interval', 60)} 分钟\n"
            f"📋 监控域名: {len(self.load_domains())} 个\n"
            f"📅 到期提醒: {', '.join(map(str, self.config.get('notify_days_before_expiry', [30, 7, 3, 1])))} 天\n\n"
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
        logging.info(f"监控域名数量: {len(self.load_domains())}")
        
        # 测试通知
        if self.config.get('telegram', {}).get('bot_token'):
            self.test_notification()
        else:
            logging.warning("未配置Telegram通知")
            
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
