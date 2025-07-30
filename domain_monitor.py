#!/usr/bin/env python3
"""
Domain Monitor - 域名监控系统
GitHub: https://github.com/everett7623/domainmonitor

功能:
- 自动监控域名注册状态
- Telegram Bot 通知
- 域名到期提醒
- 详细的日志记录
"""

import os
import sys
import json
import time
import logging
import argparse
import datetime
import socket
from typing import Dict, List, Optional, Tuple
from pathlib import Path

# 第三方库
try:
    import requests
    import whois
    import schedule
    from telegram import Bot
    from telegram.error import TelegramError
    from colorama import init, Fore, Style
    from tabulate import tabulate
except ImportError as e:
    print(f"错误: 缺少必要的依赖包 - {e}")
    print("请运行: pip install -r requirements.txt")
    sys.exit(1)

# 初始化 colorama
init(autoreset=True)

# 配置路径
BASE_DIR = Path.home() / ".domainmonitor"
CONFIG_FILE = BASE_DIR / "config.json"
LOG_DIR = BASE_DIR / "logs"
LOG_FILE = LOG_DIR / "domainmonitor.log"
HISTORY_FILE = LOG_DIR / "check_history.log"

# 创建必要的目录
BASE_DIR.mkdir(exist_ok=True)
LOG_DIR.mkdir(exist_ok=True)


class ColoredFormatter(logging.Formatter):
    """带颜色的日志格式化器"""
    
    COLORS = {
        'DEBUG': Fore.CYAN,
        'INFO': Fore.GREEN,
        'WARNING': Fore.YELLOW,
        'ERROR': Fore.RED,
        'CRITICAL': Fore.RED + Style.BRIGHT,
    }
    
    def format(self, record):
        log_color = self.COLORS.get(record.levelname, '')
        record.levelname = f"{log_color}{record.levelname}{Style.RESET_ALL}"
        return super().format(record)


def setup_logging(log_level: str = "INFO") -> logging.Logger:
    """设置日志系统"""
    logger = logging.getLogger("DomainMonitor")
    logger.setLevel(getattr(logging, log_level.upper()))
    
    # 文件处理器
    file_handler = logging.FileHandler(LOG_FILE, encoding='utf-8')
    file_formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s'
    )
    file_handler.setFormatter(file_formatter)
    
    # 控制台处理器
    console_handler = logging.StreamHandler()
    console_formatter = ColoredFormatter(
        '%(asctime)s - %(levelname)s - %(message)s',
        datefmt='%H:%M:%S'
    )
    console_handler.setFormatter(console_formatter)
    
    logger.addHandler(file_handler)
    logger.addHandler(console_handler)
    
    return logger


class Config:
    """配置管理类"""
    
    def __init__(self, config_file: Path = CONFIG_FILE):
        self.config_file = config_file
        self.data = self.load()
    
    def load(self) -> dict:
        """加载配置"""
        if not self.config_file.exists():
            return self.get_default_config()
        
        try:
            with open(self.config_file, 'r', encoding='utf-8') as f:
                return json.load(f)
        except Exception as e:
            logger.error(f"加载配置文件失败: {e}")
            return self.get_default_config()
    
    def save(self) -> None:
        """保存配置"""
        try:
            with open(self.config_file, 'w', encoding='utf-8') as f:
                json.dump(self.data, f, indent=4, ensure_ascii=False)
            logger.info("配置已保存")
        except Exception as e:
            logger.error(f"保存配置失败: {e}")
    
    @staticmethod
    def get_default_config() -> dict:
        """获取默认配置"""
        return {
            "domains": [],
            "telegram": {
                "bot_token": "",
                "chat_id": ""
            },
            "check_interval": 3600,  # 秒
            "log_level": "INFO",
            "registrars": [
                {
                    "name": "Namecheap",
                    "url": "https://www.namecheap.com",
                    "features": ["价格优惠", "免费隐私保护", "支持支付宝"]
                },
                {
                    "name": "Cloudflare",
                    "url": "https://www.cloudflare.com/products/registrar/",
                    "features": ["成本价注册", "免费 CDN", "无隐藏费用"]
                },
                {
                    "name": "阿里云",
                    "url": "https://wanwang.aliyun.com",
                    "features": ["国内访问快", "中文支持", "企业服务"]
                }
            ]
        }
    
    def get(self, key: str, default=None):
        """获取配置项"""
        return self.data.get(key, default)
    
    def set(self, key: str, value) -> None:
        """设置配置项"""
        self.data[key] = value
        self.save()


class DomainChecker:
    """域名检查器"""
    
    def __init__(self, config: Config):
        self.config = config
        self.logger = logging.getLogger("DomainMonitor.Checker")
    
    def check_domain(self, domain: str) -> Dict:
        """检查单个域名状态"""
        result = {
            "domain": domain,
            "available": False,
            "expiry_date": None,
            "registrar": None,
            "error": None,
            "check_time": datetime.datetime.now().isoformat()
        }
        
        try:
            # 首先尝试 DNS 查询
            try:
                socket.gethostbyname(domain)
                dns_exists = True
            except socket.gaierror:
                dns_exists = False
            
            # 使用 whois 查询
            try:
                w = whois.whois(domain)
                
                if w.domain_name is None:
                    result["available"] = True
                else:
                    result["available"] = False
                    result["expiry_date"] = self._parse_date(w.expiration_date)
                    result["registrar"] = w.registrar
                    
                    # 检查是否即将到期
                    if result["expiry_date"]:
                        days_until_expiry = (result["expiry_date"] - datetime.datetime.now()).days
                        if days_until_expiry <= 30:
                            result["expiry_warning"] = f"域名将在 {days_until_expiry} 天后到期！"
            
            except Exception as e:
                # 如果 whois 查询失败但 DNS 不存在，可能域名可用
                if not dns_exists:
                    result["available"] = True
                else:
                    result["error"] = str(e)
                    
        except Exception as e:
            result["error"] = f"检查失败: {str(e)}"
            self.logger.error(f"检查域名 {domain} 时出错: {e}")
        
        # 记录历史
        self._save_history(result)
        
        return result
    
    def check_all_domains(self) -> List[Dict]:
        """检查所有配置的域名"""
        domains = self.config.get("domains", [])
        results = []
        
        self.logger.info(f"开始检查 {len(domains)} 个域名...")
        
        for domain in domains:
            self.logger.info(f"正在检查: {domain}")
            result = self.check_domain(domain)
            results.append(result)
            
            # 发送通知（如果需要）
            if result["available"]:
                self._send_notification(result)
            elif result.get("expiry_warning"):
                self._send_notification(result, is_expiry_warning=True)
            
            time.sleep(1)  # 避免请求过快
        
        self.logger.info("域名检查完成")
        return results
    
    def _parse_date(self, date_value) -> Optional[datetime.datetime]:
        """解析日期"""
        if date_value is None:
            return None
        
        if isinstance(date_value, datetime.datetime):
            return date_value
        
        if isinstance(date_value, list) and date_value:
            return date_value[0] if isinstance(date_value[0], datetime.datetime) else None
        
        return None
    
    def _save_history(self, result: Dict) -> None:
        """保存检查历史"""
        try:
            with open(HISTORY_FILE, 'a', encoding='utf-8') as f:
                f.write(json.dumps(result, ensure_ascii=False) + '\n')
        except Exception as e:
            self.logger.error(f"保存历史记录失败: {e}")
    
    def _send_notification(self, result: Dict, is_expiry_warning: bool = False) -> None:
        """发送通知"""
        telegram_config = self.config.get("telegram", {})
        if not telegram_config.get("bot_token") or not telegram_config.get("chat_id"):
            return
        
        try:
            bot = Bot(token=telegram_config["bot_token"])
            
            if is_expiry_warning:
                message = self._format_expiry_message(result)
            else:
                message = self._format_available_message(result)
            
            bot.send_message(
                chat_id=telegram_config["chat_id"],
                text=message,
                parse_mode='HTML'
            )
            
            self.logger.info(f"通知已发送: {result['domain']}")
            
        except Exception as e:
            self.logger.error(f"发送通知失败: {e}")
    
    def _format_available_message(self, result: Dict) -> str:
        """格式化可用域名通知消息"""
        registrars = self.config.get("registrars", [])
        
        message = f"""
🎉 <b>域名可以注册！</b>

📌 <b>域名:</b> {result['domain']}
⏰ <b>检测时间:</b> {datetime.datetime.now().strftime('%Y-%m-%d %H:%M:%S')}
✅ <b>状态:</b> 可注册

<b>📋 推荐注册商:</b>
"""
        
        for reg in registrars[:3]:  # 只显示前3个
            features = "、".join(reg['features'][:2])
            message += f"\n• <b>{reg['name']}</b> - {features}"
            message += f"\n  🔗 {reg['url']}"
        
        message += """

<b>💡 注册建议:</b>
• 建议注册 3-5 年，获得更多优惠
• 开启域名隐私保护
• 设置自动续费避免过期
• 立即注册，好域名不等人！

⚡ <b>紧急提醒:</b> 好域名随时可能被他人注册，请尽快行动！
"""
        
        return message
    
    def _format_expiry_message(self, result: Dict) -> str:
        """格式化域名到期提醒消息"""
        days_until_expiry = (result["expiry_date"] - datetime.datetime.now()).days
        
        message = f"""
⚠️ <b>域名即将到期！</b>

📌 <b>域名:</b> {result['domain']}
📅 <b>到期时间:</b> {result['expiry_date'].strftime('%Y-%m-%d')}
⏳ <b>剩余天数:</b> {days_until_expiry} 天
🏢 <b>当前注册商:</b> {result.get('registrar', '未知')}

<b>⚡ 紧急行动:</b>
• 立即登录注册商后台续费
• 建议一次续费 3-5 年
• 检查域名转移锁状态
• 更新域名联系信息

<b>💡 温馨提示:</b>
域名过期后有赎回期，费用会大幅增加。请务必在到期前完成续费！
"""
        
        return message


class DomainMonitorCLI:
    """命令行界面"""
    
    def __init__(self):
        self.config = Config()
        self.checker = DomainChecker(self.config)
        self.logger = logging.getLogger("DomainMonitor.CLI")
    
    def run(self):
        """运行主菜单"""
        while True:
            self.clear_screen()
            self.print_header()
            self.print_menu()
            
            choice = input(f"\n{Fore.CYAN}请选择操作 [1-7]: {Style.RESET_ALL}")
            
            if choice == '1':
                self.add_domain()
            elif choice == '2':
                self.remove_domain()
            elif choice == '3':
                self.setup_telegram()
            elif choice == '4':
                self.remove_telegram()
            elif choice == '5':
                self.view_domains()
            elif choice == '6':
                self.uninstall()
            elif choice == '7':
                print(f"\n{Fore.GREEN}感谢使用 Domain Monitor！再见！{Style.RESET_ALL}")
                break
            else:
                print(f"\n{Fore.RED}无效选择，请重试{Style.RESET_ALL}")
                time.sleep(1)
    
    def clear_screen(self):
        """清屏"""
        os.system('clear' if os.name == 'posix' else 'cls')
    
    def print_header(self):
        """打印头部"""
        print(f"""
{Fore.CYAN}╔══════════════════════════════════════════════╗
║       {Fore.YELLOW}Domain Monitor - 域名监控系统{Fore.CYAN}          ║
║                                              ║
║         {Fore.GREEN}GitHub: @everett7623{Fore.CYAN}                ║
╚══════════════════════════════════════════════╝{Style.RESET_ALL}
""")
    
    def print_menu(self):
        """打印菜单"""
        print(f"""
{Fore.YELLOW}━━━━━━━━━━━━━━ 主菜单 ━━━━━━━━━━━━━━{Style.RESET_ALL}

  {Fore.GREEN}1.{Style.RESET_ALL} 📝 添加监控域名
  {Fore.GREEN}2.{Style.RESET_ALL} 🗑️  删除监控域名
  {Fore.GREEN}3.{Style.RESET_ALL} 📱 添加 Telegram Bot 通知
  {Fore.GREEN}4.{Style.RESET_ALL} 🔕 删除 Telegram Bot 通知
  {Fore.GREEN}5.{Style.RESET_ALL} 👀 查看监控域名
  {Fore.GREEN}6.{Style.RESET_ALL} 💣 删除监控域名和脚本
  {Fore.GREEN}7.{Style.RESET_ALL} 🚪 退出

{Fore.YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━{Style.RESET_ALL}""")
    
    def add_domain(self):
        """添加域名"""
        self.clear_screen()
        print(f"\n{Fore.CYAN}=== 添加监控域名 ==={Style.RESET_ALL}\n")
        
        domains = self.config.get("domains", [])
        
        while True:
            domain = input(f"{Fore.YELLOW}请输入域名 (直接回车返回): {Style.RESET_ALL}").strip().lower()
            
            if not domain:
                break
            
            # 验证域名格式
            if not self._validate_domain(domain):
                print(f"{Fore.RED}❌ 域名格式无效，请输入正确的域名{Style.RESET_ALL}")
                continue
            
            if domain in domains:
                print(f"{Fore.YELLOW}⚠️  域名已在监控列表中{Style.RESET_ALL}")
            else:
                domains.append(domain)
                self.config.set("domains", domains)
                print(f"{Fore.GREEN}✅ 已添加: {domain}{Style.RESET_ALL}")
                
                # 立即检查一次
                print(f"{Fore.CYAN}正在检查域名状态...{Style.RESET_ALL}")
                result = self.checker.check_domain(domain)
                self._display_check_result(result)
        
        input(f"\n{Fore.CYAN}按回车键返回主菜单...{Style.RESET_ALL}")
    
    def remove_domain(self):
        """删除域名"""
        self.clear_screen()
        print(f"\n{Fore.CYAN}=== 删除监控域名 ==={Style.RESET_ALL}\n")
        
        domains = self.config.get("domains", [])
        
        if not domains:
            print(f"{Fore.YELLOW}监控列表为空{Style.RESET_ALL}")
            input(f"\n{Fore.CYAN}按回车键返回主菜单...{Style.RESET_ALL}")
            return
        
        # 显示域名列表
        for i, domain in enumerate(domains, 1):
            print(f"  {Fore.GREEN}{i}.{Style.RESET_ALL} {domain}")
        
        print(f"\n  {Fore.YELLOW}0.{Style.RESET_ALL} 返回主菜单")
        
        try:
            choice = int(input(f"\n{Fore.CYAN}请选择要删除的域名编号: {Style.RESET_ALL}"))
            
            if choice == 0:
                return
            
            if 1 <= choice <= len(domains):
                removed_domain = domains.pop(choice - 1)
                self.config.set("domains", domains)
                print(f"\n{Fore.GREEN}✅ 已删除: {removed_domain}{Style.RESET_ALL}")
            else:
                print(f"\n{Fore.RED}❌ 无效选择{Style.RESET_ALL}")
        
        except ValueError:
            print(f"\n{Fore.RED}❌ 请输入数字{Style.RESET_ALL}")
        
        input(f"\n{Fore.CYAN}按回车键返回主菜单...{Style.RESET_ALL}")
    
    def setup_telegram(self):
        """设置 Telegram"""
        self.clear_screen()
        print(f"\n{Fore.CYAN}=== 设置 Telegram Bot 通知 ==={Style.RESET_ALL}\n")
        
        print(f"{Fore.YELLOW}设置步骤:{Style.RESET_ALL}")
        print("1. 在 Telegram 中搜索 @BotFather")
        print("2. 发送 /newbot 创建新机器人")
        print("3. 按提示设置机器人名称和用户名")
        print("4. 获取 Bot Token")
        print("5. 启动机器人并发送任意消息")
        print("6. 获取您的 Chat ID\n")
        
        bot_token = input(f"{Fore.CYAN}请输入 Bot Token: {Style.RESET_ALL}").strip()
        
        if bot_token:
            chat_id = input(f"{Fore.CYAN}请输入 Chat ID: {Style.RESET_ALL}").strip()
            
            if chat_id:
                telegram_config = {
                    "bot_token": bot_token,
                    "chat_id": chat_id
                }
                self.config.set("telegram", telegram_config)
                
                # 测试发送消息
                print(f"\n{Fore.CYAN}正在测试 Telegram 连接...{Style.RESET_ALL}")
                try:
                    bot = Bot(token=bot_token)
                    bot.send_message(
                        chat_id=chat_id,
                        text="🎉 Domain Monitor 配置成功！\n\n您将在这里收到域名状态通知。"
                    )
                    print(f"{Fore.GREEN}✅ Telegram 配置成功！{Style.RESET_ALL}")
                except Exception as e:
                    print(f"{Fore.RED}❌ 配置失败: {e}{Style.RESET_ALL}")
                    print(f"{Fore.YELLOW}请检查 Token 和 Chat ID 是否正确{Style.RESET_ALL}")
        
        input(f"\n{Fore.CYAN}按回车键返回主菜单...{Style.RESET_ALL}")
    
    def remove_telegram(self):
        """删除 Telegram 配置"""
        self.clear_screen()
        print(f"\n{Fore.CYAN}=== 删除 Telegram Bot 通知 ==={Style.RESET_ALL}\n")
        
        telegram_config = self.config.get("telegram", {})
        
        if not telegram_config.get("bot_token"):
            print(f"{Fore.YELLOW}未配置 Telegram 通知{Style.RESET_ALL}")
        else:
            confirm = input(f"{Fore.YELLOW}确定要删除 Telegram 配置吗？(y/N): {Style.RESET_ALL}")
            
            if confirm.lower() == 'y':
                self.config.set("telegram", {"bot_token": "", "chat_id": ""})
                print(f"\n{Fore.GREEN}✅ Telegram 配置已删除{Style.RESET_ALL}")
        
        input(f"\n{Fore.CYAN}按回车键返回主菜单...{Style.RESET_ALL}")
    
    def view_domains(self):
        """查看监控域名"""
        self.clear_screen()
        print(f"\n{Fore.CYAN}=== 监控域名列表 ==={Style.RESET_ALL}\n")
        
        domains = self.config.get("domains", [])
        
        if not domains:
            print(f"{Fore.YELLOW}监控列表为空{Style.RESET_ALL}")
        else:
            print(f"{Fore.YELLOW}正在检查所有域名状态，请稍候...{Style.RESET_ALL}\n")
            
            results = []
            for domain in domains:
                result = self.checker.check_domain(domain)
                results.append([
                    domain,
                    "✅ 可注册" if result["available"] else "❌ 已注册",
                    result.get("registrar", "-") if not result["available"] else "-",
                    result["expiry_date"].strftime("%Y-%m-%d") if result.get("expiry_date") else "-"
                ])
                time.sleep(0.5)
            
            # 使用表格显示
            headers = ["域名", "状态", "注册商", "到期时间"]
            print(tabulate(results, headers=headers, tablefmt="grid"))
            
            # 显示 Telegram 状态
            telegram_config = self.config.get("telegram", {})
            telegram_status = "✅ 已配置" if telegram_config.get("bot_token") else "❌ 未配置"
            print(f"\n{Fore.CYAN}Telegram 通知: {telegram_status}{Style.RESET_ALL}")
        
        input(f"\n{Fore.CYAN}按回车键返回主菜单...{Style.RESET_ALL}")
    
    def uninstall(self):
        """卸载程序"""
        self.clear_screen()
        print(f"\n{Fore.RED}=== 卸载 Domain Monitor ==={Style.RESET_ALL}\n")
        
        print(f"{Fore.YELLOW}此操作将删除:{Style.RESET_ALL}")
        print(f"  • 所有配置文件")
        print(f"  • 日志文件")
        print(f"  • 定时任务")
        print(f"  • 程序文件\n")
        
        confirm = input(f"{Fore.RED}确定要完全卸载吗？(y/N): {Style.RESET_ALL}")
        
        if confirm.lower() == 'y':
            double_confirm = input(f"{Fore.RED}请再次确认 (输入 'DELETE' 继续): {Style.RESET_ALL}")
            
            if double_confirm == 'DELETE':
                print(f"\n{Fore.YELLOW}正在卸载...{Style.RESET_ALL}")
                
                # 删除 crontab
                os.system("crontab -l | grep -v domainmonitor | crontab -")
                
                # 删除 systemd service
                service_file = Path.home() / ".config/systemd/user/domainmonitor.service"
                if service_file.exists():
                    os.system("systemctl --user stop domainmonitor.service")
                    os.system("systemctl --user disable domainmonitor.service")
                    service_file.unlink()
                
                # 删除软链接
                for link_path in [
                    Path.home() / ".local/bin/domainmonitor",
                    Path("/usr/local/bin/domainmonitor")
                ]:
                    if link_path.exists():
                        try:
                            link_path.unlink()
                        except:
                            pass
                
                # 删除主目录
                import shutil
                shutil.rmtree(BASE_DIR, ignore_errors=True)
                
                print(f"\n{Fore.GREEN}✅ Domain Monitor 已完全卸载{Style.RESET_ALL}")
                print(f"{Fore.YELLOW}感谢您的使用！{Style.RESET_ALL}")
                sys.exit(0)
        
        input(f"\n{Fore.CYAN}按回车键返回主菜单...{Style.RESET_ALL}")
    
    def _validate_domain(self, domain: str) -> bool:
        """验证域名格式"""
        import re
        pattern = r'^(?:[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?\.)*[a-zA-Z0-9](?:[a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?
        return bool(re.match(pattern, domain))
    
    def _display_check_result(self, result: Dict):
        """显示检查结果"""
        if result.get("error"):
            print(f"{Fore.RED}检查出错: {result['error']}{Style.RESET_ALL}")
        elif result["available"]:
            print(f"{Fore.GREEN}✅ 域名可以注册！{Style.RESET_ALL}")
        else:
            print(f"{Fore.YELLOW}❌ 域名已被注册{Style.RESET_ALL}")
            if result.get("registrar"):
                print(f"   注册商: {result['registrar']}")
            if result.get("expiry_date"):
                print(f"   到期时间: {result['expiry_date'].strftime('%Y-%m-%d')}")


def daemon_mode(config: Config):
    """守护进程模式"""
    logger.info("Domain Monitor 守护进程已启动")
    
    checker = DomainChecker(config)
    interval = config.get("check_interval", 3600)
    
    # 设置定时任务
    schedule.every(interval).seconds.do(checker.check_all_domains)
    
    # 立即执行一次
    checker.check_all_domains()
    
    # 持续运行
    while True:
        schedule.run_pending()
        time.sleep(60)


def main():
    """主函数"""
    parser = argparse.ArgumentParser(description="Domain Monitor - 域名监控系统")
    parser.add_argument("--check", action="store_true", help="执行一次域名检查")
    parser.add_argument("--daemon", action="store_true", help="以守护进程模式运行")
    parser.add_argument("--list", action="store_true", help="列出所有监控的域名")
    
    args = parser.parse_args()
    
    # 加载配置
    config = Config()
    
    # 设置日志
    global logger
    logger = setup_logging(config.get("log_level", "INFO"))
    
    if args.check:
        # 执行一次检查
        checker = DomainChecker(config)
        checker.check_all_domains()
    elif args.daemon:
        # 守护进程模式
        daemon_mode(config)
    elif args.list:
        # 列出域名
        domains = config.get("domains", [])
        if domains:
            print("\n监控中的域名:")
            for domain in domains:
                print(f"  • {domain}")
        else:
            print("\n没有监控的域名")
    else:
        # 交互式菜单
        cli = DomainMonitorCLI()
        cli.run()


if __name__ == "__main__":
    main()
