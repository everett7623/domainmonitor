#!/usr/bin/env python3
"""
域名监控脚本 - 隐私增强版
添加了随机化、代理支持等隐私保护功能
"""

import random
import time
from datetime import datetime, timedelta
import whois
import requests
import json
import logging
import os
import socket
import socks  # 需要安装 PySocks

# 原有导入...
from typing import List, Dict, Optional

class PrivacyEnhancedDomainMonitor:
    def __init__(self, telegram_bot_token: str, telegram_chat_id: str):
        """初始化隐私增强版域名监控器"""
        self.bot_token = telegram_bot_token
        self.chat_id = telegram_chat_id
        self.domains_file = 'domains.json'
        self.domains = self.load_domains()
        
        # 隐私增强设置
        self.use_random_delay = True
        self.min_delay = 2  # 最小延迟（秒）
        self.max_delay = 10  # 最大延迟（秒）
        self.user_agents = [
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36'
        ]
        
        # 代理设置（可选）
        self.proxy_enabled = os.getenv('USE_PROXY', 'false').lower() == 'true'
        self.proxy_host = os.getenv('PROXY_HOST', '')
        self.proxy_port = int(os.getenv('PROXY_PORT', '1080'))
        
        if self.proxy_enabled:
            self.setup_proxy()
    
    def setup_proxy(self):
        """设置 SOCKS 代理"""
        if self.proxy_host:
            socks.set_default_proxy(socks.SOCKS5, self.proxy_host, self.proxy_port)
            socket.socket = socks.socksocket
            logging.info(f"已启用代理: {self.proxy_host}:{self.proxy_port}")
    
    def random_delay(self):
        """添加随机延迟"""
        if self.use_random_delay:
            delay = random.uniform(self.min_delay, self.max_delay)
            logging.debug(f"随机延迟 {delay:.2f} 秒")
            time.sleep(delay)
    
    def get_random_user_agent(self):
        """获取随机 User-Agent"""
        return random.choice(self.user_agents)
    
    def check_domain_with_privacy(self, domain: str) -> Dict:
        """隐私增强的域名检查"""
        # 添加随机延迟
        self.random_delay()
        
        # 随机化查询时间（±10分钟）
        if random.random() < 0.3:  # 30% 概率延迟
            extra_delay = random.randint(0, 600)  # 0-10分钟
            logging.info(f"额外随机延迟 {extra_delay} 秒")
            time.sleep(extra_delay)
        
        result = {
            'domain': domain,
            'available': False,
            'expiry_date': None,
            'registrar': None,
            'check_time': datetime.now().isoformat(),
            'check_method': 'unknown'
        }
        
        try:
            # 方法1：尝试多个 WHOIS 服务器
            whois_servers = [
                'whois.verisign-grs.com',  # .com/.net
                'whois.pir.org',            # .org
                'whois.iana.org'            # 通用
            ]
            
            for server in whois_servers:
                try:
                    w = whois.whois(domain, server=server)
                    if w.domain_name:
                        result['available'] = False
                        result['expiry_date'] = str(w.expiration_date) if w.expiration_date else None
                        result['registrar'] = w.registrar
                        result['check_method'] = f'whois_{server}'
                        break
                    else:
                        result['available'] = True
                        result['check_method'] = f'whois_{server}'
                        break
                except:
                    continue
            
            # 方法2：使用 HTTP API（备选）
            if result['check_method'] == 'unknown':
                # 可以使用一些公开的 WHOIS API
                # 这里仅作示例
                pass
                
        except Exception as e:
            logging.error(f"检查域名 {domain} 时出错: {e}")
            result['error'] = str(e)
        
        return result
    
    def run_with_random_schedule(self, base_interval_minutes: int = 60):
        """使用随机化的检查计划"""
        logging.info(f"启动隐私增强版域名监控，基础间隔: {base_interval_minutes} 分钟")
        
        while True:
            # 检查所有域名
            self.check_all_domains()
            
            # 计算下次检查时间（基础间隔 ± 20%）
            variation = base_interval_minutes * 0.2
            next_interval = base_interval_minutes + random.uniform(-variation, variation)
            next_check_time = datetime.now() + timedelta(minutes=next_interval)
            
            logging.info(f"下次检查时间: {next_check_time.strftime('%Y-%m-%d %H:%M:%S')} ({next_interval:.1f} 分钟后)")
            
            # 等待到下次检查
            time.sleep(next_interval * 60)
    
    # 其他方法继承自原始类...

# 隐私保护建议配置
"""
环境变量配置示例：

# 启用代理
USE_PROXY=true
PROXY_HOST=127.0.0.1
PROXY_PORT=1080

# 使用 Tor 网络（需要先安装 Tor）
# apt-get install tor
# systemctl start tor
# 然后设置 PROXY_HOST=127.0.0.1 PROXY_PORT=9050
"""

def setup_tor():
    """设置 Tor 代理的辅助函数"""
    print("设置 Tor 代理...")
    print("1. 安装 Tor: sudo apt-get install tor")
    print("2. 启动 Tor: sudo systemctl start tor")
    print("3. 设置环境变量:")
    print("   export USE_PROXY=true")
    print("   export PROXY_HOST=127.0.0.1")
    print("   export PROXY_PORT=9050")

if __name__ == '__main__':
    # 检查是否需要设置 Tor
    if '--setup-tor' in sys.argv:
        setup_tor()
        sys.exit(0)
    
    # 正常运行...
