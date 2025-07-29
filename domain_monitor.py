#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import whois
import telegram
import logging
import configparser
from datetime import datetime

# --- 全局设置 ---
# 将工作目录设置为脚本所在目录，确保在任何路径下执行都能找到相关文件
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
os.chdir(BASE_DIR)

CONFIG_FILE = 'config.ini'
DOMAINS_FILE = 'domains.txt'
HISTORY_LOG_FILE = 'history.log'
RUN_LOG_FILE = 'run.log'
EXPIRATION_REMINDER_DAYS = 30 # 提前30天发送到期提醒

# --- 日志配置 ---
# 运行日志，记录脚本每次运行的详细过程
run_logger = logging.getLogger('run_logger')
run_logger.setLevel(logging.INFO)
run_handler = logging.FileHandler(RUN_LOG_FILE)
run_handler.setFormatter(logging.Formatter('%(asctime)s - %(levelname)s - %(message)s'))
run_logger.addHandler(run_handler)

# 历史日志，只记录域名的状态变更
history_logger = logging.getLogger('history_logger')
history_logger.setLevel(logging.INFO)
history_handler = logging.FileHandler(HISTORY_LOG_FILE)
history_handler.setFormatter(logging.Formatter('%(asctime)s - %(message)s'))
history_logger.addHandler(history_handler)


def load_config():
    """加载配置文件"""
    try:
        config = configparser.ConfigParser()
        if not os.path.exists(CONFIG_FILE):
            run_logger.error(f"配置文件 {CONFIG_FILE} 未找到!")
            return None, None
        config.read(CONFIG_FILE)
        return config['telegram']['bot_token'], config['telegram']['chat_id']
    except Exception as e:
        run_logger.error(f"读取配置文件时出错: {e}")
        return None, None

def load_domains():
    """加载域名列表"""
    try:
        if not os.path.exists(DOMAINS_FILE):
            run_logger.error(f"域名文件 {DOMAINS_FILE} 未找到!")
            return []
        with open(DOMAINS_FILE, 'r') as f:
            # 去除空行和首尾空格
            domains = [line.strip() for line in f if line.strip()]
        return domains
    except Exception as e:
        run_logger.error(f"读取域名文件时出错: {e}")
        return []

def send_telegram_notification(bot_token, chat_id, message):
    """发送Telegram通知"""
    try:
        bot = telegram.Bot(token=bot_token)
        bot.send_message(chat_id=chat_id, text=message, parse_mode=telegram.ParseMode.MARKDOWN)
        run_logger.info(f"成功发送通知到 Chat ID: {chat_id}")
    except Exception as e:
        run_logger.error(f"发送Telegram通知失败: {e}")

def check_domain_status(domain):
    """
    检查单个域名的状态
    返回: (status, expiration_date)
    status: 'available', 'registered', 'error'
    """
    run_logger.info(f"开始检查域名: {domain}")
    try:
        w = whois.whois(domain)
        # python-whois库的一个特点：如果域名未注册，其creation_date和expiration_date通常为None
        if w.status is None or w.creation_date is None:
            return 'available', None
        else:
            # 如果是列表，取第一个日期
            exp_date = w.expiration_date
            if isinstance(exp_date, list):
                exp_date = exp_date[0]
            return 'registered', exp_date
    except Exception as e:
        run_logger.warning(f"查询域名 {domain} 时出现异常: {e}")
        # 某些 .cn 或特殊域名查询会抛出异常，但可能已被注册
        # 我们可以认为查询异常的域名不是我们想要的“明确可注册”状态
        return 'error', None


def main():
    """主执行函数"""
    run_logger.info("====== 开始新一轮域名监控 ======")
    bot_token, chat_id = load_config()
    if not bot_token or not chat_id:
        run_logger.error("无法加载Telegram配置，脚本退出。")
        return

    domains = load_domains()
    if not domains:
        run_logger.warning("域名列表为空，无需执行。")
        return

    for domain in domains:
        status, expiration_date = check_domain_status(domain)
        current_time = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        if status == 'available':
            history_logger.info(f"【可注册】域名: {domain}")
            message = (
                f"🚨 *域名可注册提醒* 🚨\n\n"
                f"*域名名称*: `{domain}`\n"
                f"*当前状态*: ✅ *可以注册!*\n"
                f"*检测时间*: {current_time}\n\n"
                f"--- *注册建议* ---\n"
                f"🔹 *推荐注册商*:\n"
                f"  - NameSilo (隐私保护免费)\n"
                f"  - GoDaddy (全球最大)\n"
                f"  - Cloudflare (成本价)\n"
                f"🔹 *注册年限*: 建议注册多年以锁定价格并利于SEO。\n"
                f"🔹 *隐私保护*: 强烈建议开启Whois隐私保护，防止垃圾邮件。\n\n"
                f"❗️ *紧急行动提醒*: 好域名非常抢手，请立即行动！"
            )
            send_telegram_notification(bot_token, chat_id, message)

        elif status == 'registered':
            history_logger.info(f"【已注册】域名: {domain}, 到期日: {expiration_date}")
            if expiration_date:
                time_diff = expiration_date - datetime.now()
                if 0 < time_diff.days <= EXPIRATION_REMINDER_DAYS:
                    message = (
                        f"⏰ *域名到期提醒* ⏰\n\n"
                        f"*域名名称*: `{domain}`\n"
                        f"*状态*: 🔴 *即将到期!*\n"
                        f"*到期日期*: {expiration_date.strftime('%Y-%m-%d')}\n"
                        f"*剩余时间*: {time_diff.days} 天\n\n"
                        f"请及时续费，防止域名被抢注！"
                    )
                    send_telegram_notification(bot_token, chat_id, message)

        elif status == 'error':
            history_logger.info(f"【查询错误】域名: {domain}")
            # 对于查询错误的域名，我们通常不发送通知，只记录日志

    run_logger.info("====== 本轮域名监控结束 ======\n")


if __name__ == "__main__":
    main()
