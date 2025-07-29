#!/usr/bin/env python3
"""
域名监控服务 - 交互式菜单
简单易用的一键管理系统
"""

import os
import sys
import json
import subprocess
import time
from datetime import datetime

# 颜色定义
RED = '\033[0;31m'
GREEN = '\033[0;32m'
YELLOW = '\033[1;33m'
BLUE = '\033[0;34m'
CYAN = '\033[0;36m'
NC = '\033[0m'  # No Color
BOLD = '\033[1m'

class DomainMonitorMenu:
    def __init__(self):
        self.config_file = 'config.json'
        self.load_config()
        
    def load_config(self):
        """加载配置"""
        if os.path.exists(self.config_file):
            with open(self.config_file, 'r') as f:
                self.config = json.load(f)
        else:
            self.config = {
                'telegram_bot_token': '',
                'telegram_chat_id': '',
                'check_interval_minutes': 60,
                'domains': {}
            }
    
    def save_config(self):
        """保存配置"""
        with open(self.config_file, 'w') as f:
            json.dump(self.config, f, ensure_ascii=False, indent=2)
        os.chmod(self.config_file, 0o600)
    
    def clear_screen(self):
        """清屏"""
        os.system('clear' if os.name == 'posix' else 'cls')
    
    def print_header(self):
        """打印标题"""
        self.clear_screen()
        print(f"{CYAN}{'='*60}{NC}")
        print(f"{BOLD}{BLUE}           域名监控服务 - 简单管理菜单{NC}")
        print(f"{CYAN}{'='*60}{NC}\n")
    
    def print_status(self):
        """显示状态"""
        # Telegram 配置状态
        if self.config['telegram_bot_token'] and self.config['telegram_chat_id']:
            print(f"{GREEN}● Telegram 已配置{NC}")
        else:
            print(f"{RED}● Telegram 未配置{NC}")
        
        # 服务状态
        try:
            result = subprocess.run(['supervisorctl', 'status', 'domain-monitor'], 
                                  capture_output=True, text=True)
            if 'RUNNING' in result.stdout:
                print(f"{GREEN}● 监控服务运行中{NC}")
            else:
                print(f"{RED}● 监控服务已停止{NC}")
        except:
            print(f"{YELLOW}● 服务状态未知{NC}")
        
        # 域名数量
        domain_count = len(self.config.get('domains', {}))
        print(f"{BLUE}● 监控域名数量：{domain_count}{NC}\n")
    
    def configure_telegram(self):
        """配置 Telegram"""
        self.print_header()
        print(f"{YELLOW}配置 Telegram Bot{NC}\n")
        
        print("获取 Bot Token:")
        print("1. Telegram 搜索 @BotFather")
        print("2. 发送 /newbot 创建机器人")
        print("3. 复制 Token\n")
        
        token = input("Bot Token: ").strip()
        if not token:
            print(f"{RED}Token 不能为空！{NC}")
            time.sleep(2)
            return
        
        print("\n获取 Chat ID:")
        print("1. 给 Bot 发送消息")
        print(f"2. 访问: https://api.telegram.org/bot{token}/getUpdates")
        print("3. 找到 chat.id 的值\n")
        
        chat_id = input("Chat ID: ").strip()
        if not chat_id:
            print(f"{RED}Chat ID 不能为空！{NC}")
            time.sleep(2)
            return
        
        # 验证配置
        import requests
        print(f"\n{YELLOW}验证配置...{NC}")
        try:
            url = f"https://api.telegram.org/bot{token}/sendMessage"
            response = requests.post(url, data={
                'chat_id': chat_id,
                'text': '✅ 域名监控配置成功！',
                'parse_mode': 'HTML'
            })
            
            if response.json().get('ok'):
                self.config['telegram_bot_token'] = token
                self.config['telegram_chat_id'] = chat_id
                self.save_config()
                print(f"{GREEN}✓ 配置成功！{NC}")
            else:
                print(f"{RED}✗ 配置失败，请检查 Token 和 Chat ID{NC}")
        except Exception as e:
            print(f"{RED}✗ 验证失败: {e}{NC}")
        
        input("\n按回车返回...")
    
    def manage_domains(self):
        """域名管理"""
        while True:
            self.print_header()
            print(f"{YELLOW}域名管理{NC}\n")
            
            # 显示当前域名
            domains = self.config.get('domains', {})
            if domains:
                print("当前监控的域名:")
                print("-" * 50)
                for domain, info in domains.items():
                    status = info.get('status', '未知')
                    if status == 'available':
                        status = f"{GREEN}可注册{NC}"
                    elif status == 'registered':
                        status = f"{RED}已注册{NC}"
                    
                    print(f"• {domain:<30} {status}")
                    if info.get('notes'):
                        print(f"  备注: {info['notes']}")
                print("-" * 50)
            else:
                print("暂无监控的域名")
            
            print(f"\n{CYAN}操作选项：{NC}")
            print("1. 添加域名")
            print("2. 删除域名")
            print("3. 立即检查所有域名")
            print("0. 返回主菜单")
            
            choice = input("\n请选择 [0-3]: ").strip()
            
            if choice == '1':
                domain = input("\n域名: ").strip().lower()
                if domain and '.' in domain:
                    notes = input("备注 (可选): ").strip()
                    self.config['domains'][domain] = {
                        'added_at': datetime.now().isoformat(),
                        'status': 'unknown',
                        'notes': notes,
                        'notified': False
                    }
                    self.save_config()
                    print(f"{GREEN}✓ 已添加: {domain}{NC}")
                    time.sleep(1)
                
            elif choice == '2':
                domain = input("\n要删除的域名: ").strip().lower()
                if domain in self.config['domains']:
                    del self.config['domains'][domain]
                    self.save_config()
                    print(f"{GREEN}✓ 已删除: {domain}{NC}")
                else:
                    print(f"{RED}域名不存在{NC}")
                time.sleep(1)
                
            elif choice == '3':
                print(f"\n{YELLOW}正在检查所有域名...{NC}")
                os.system('cd /opt/domain-monitor && source venv/bin/activate && python3 -c "from domain_monitor import DomainMonitor; m = DomainMonitor(); m.check_all_domains()"')
                input("\n按回车继续...")
                
            elif choice == '0':
                break
    
    def service_control(self):
        """服务控制"""
        self.print_header()
        print(f"{YELLOW}服务控制{NC}\n")
        
        print("1. 启动服务")
        print("2. 停止服务")
        print("3. 重启服务")
        print("4. 查看日志")
        print("0. 返回")
        
        choice = input("\n请选择 [0-4]: ").strip()
        
        if choice == '1':
            os.system('supervisorctl start domain-monitor')
            print(f"{GREEN}✓ 启动命令已执行{NC}")
        elif choice == '2':
            os.system('supervisorctl stop domain-monitor')
            print(f"{YELLOW}✓ 停止命令已执行{NC}")
        elif choice == '3':
            os.system('supervisorctl restart domain-monitor')
            print(f"{GREEN}✓ 重启命令已执行{NC}")
        elif choice == '4':
            print(f"\n{YELLOW}最新日志 (Ctrl+C 退出):{NC}\n")
            os.system('tail -f /var/log/domain-monitor.log')
        
        if choice in ['1', '2', '3']:
            time.sleep(2)
    
    def quick_start(self):
        """快速开始向导"""
        self.print_header()
        print(f"{GREEN}快速开始向导{NC}\n")
        
        # 1. 配置 Telegram
        if not self.config['telegram_bot_token']:
            print("第一步：配置 Telegram")
            input("按回车继续...")
            self.configure_telegram()
        
        # 2. 添加域名
        if not self.config.get('domains'):
            self.print_header()
            print("第二步：添加要监控的域名\n")
            
            while True:
                domain = input("域名 (直接回车结束): ").strip().lower()
                if not domain:
                    break
                if '.' in domain:
                    self.config['domains'][domain] = {
                        'added_at': datetime.now().isoformat(),
                        'status': 'unknown',
                        'notes': '',
                        'notified': False
                    }
                    print(f"{GREEN}✓ 已添加: {domain}{NC}")
            
            self.save_config()
        
        # 3. 启动服务
        self.print_header()
        print("第三步：启动监控服务\n")
        
        if input("是否立即启动服务? (y/n): ").lower() == 'y':
            os.system('supervisorctl start domain-monitor')
            print(f"{GREEN}✓ 服务已启动！{NC}")
        
        print(f"\n{GREEN}设置完成！{NC}")
        input("\n按回车返回主菜单...")
    
    def main_menu(self):
        """主菜单"""
        while True:
            self.print_header()
            self.print_status()
            
            print(f"{CYAN}主菜单：{NC}")
            print("1. 🚀 快速开始")
            print("2. 📋 域名管理")
            print("3. ⚙️  服务控制")
            print("4. 🔧 Telegram 设置")
            print("5. ⏱️  修改检查间隔")
            print("0. 退出")
            
            choice = input("\n请选择 [0-5]: ").strip()
            
            if choice == '1':
                self.quick_start()
            elif choice == '2':
                self.manage_domains()
            elif choice == '3':
                self.service_control()
            elif choice == '4':
                self.configure_telegram()
            elif choice == '5':
                self.print_header()
                print(f"当前检查间隔: {self.config.get('check_interval_minutes', 60)} 分钟\n")
                try:
                    interval = int(input("新的间隔(分钟): "))
                    if 5 <= interval <= 1440:
                        self.config['check_interval_minutes'] = interval
                        self.save_config()
                        print(f"{GREEN}✓ 已更新{NC}")
                        print(f"{YELLOW}需要重启服务生效{NC}")
                    else:
                        print(f"{RED}请输入 5-1440 之间的数字{NC}")
                except:
                    print(f"{RED}无效输入{NC}")
                time.sleep(2)
            elif choice == '0':
                print(f"\n{GREEN}再见！{NC}")
                break

if __name__ == '__main__':
    menu = DomainMonitorMenu()
    menu.main_menu()
