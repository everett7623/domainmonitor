# 域名监控系统 (Domain Monitor)

一个自动监控域名注册状态的 Python 脚本，支持 Telegram Bot 通知，帮助用户及时获知心仪域名的可注册状态。

## 功能特点

- 🔍 **自动检测**：定期检查域名的注册状态
- 📱 **即时通知**：通过 Telegram Bot 发送详细通知
- 📊 **状态追踪**：记录每个域名的检查历史
- ⏰ **到期提醒**：域名即将到期时自动提醒
- 🛠️ **易于管理**：提供简单的命令行管理工具
- 📝 **详细日志**：完整的运行日志记录

## 快速安装

```bash
bash <(curl -sSL https://raw.githubusercontent.com/everett7623/domainmonitor/main/install.sh)
```

## Telegram通知问题修复

### 问题原因
1. **网络连接问题**：服务器无法访问Telegram API
2. **配置错误**：Bot Token或Chat ID配置不正确
3. **依赖问题**：python-telegram-bot版本不兼容

### 解决方案

#### 1. 检查网络连接
```bash
# 测试是否能访问Telegram API
curl -s https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getMe
```

#### 2. 验证配置
```bash
# 查看当前配置
cat /opt/domainmonitor/config.json

# 测试Bot Token是否有效
curl -s "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getMe" | python3 -m json.tool
```

#### 3. 获取正确的Chat ID
```bash
# 1. 给你的Bot发送一条消息
# 2. 然后访问以下URL获取Chat ID
curl -s "https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates" | python3 -m json.tool
```

#### 4. 手动测试通知
```python
# 创建测试脚本 test_telegram.py
import requests

bot_token = "YOUR_BOT_TOKEN"
chat_id = "YOUR_CHAT_ID"

url = f"https://api.telegram.org/bot{bot_token}/sendMessage"
data = {
    'chat_id': chat_id,
    'text': '测试消息：域名监控系统正常工作！'
}

response = requests.post(url, data=data)
print(response.json())
```

#### 5. 使用代理（如果在中国大陆）
```bash
# 编辑 /opt/domainmonitor/domain_monitor.py
# 在requests中添加代理
proxies = {
    'http': 'http://127.0.0.1:7890',
    'https': 'http://127.0.0.1:7890',
}
response = requests.post(url, data=data, proxies=proxies, timeout=10)
```

## 管理命令

运行管理脚本：
```bash
/opt/domainmonitor/manage.sh
```

### 菜单选项
1. **添加监控域名** - 添加新的域名到监控列表
2. **删除监控域名** - 从监控列表中删除域名
3. **配置Telegram Bot通知** - 设置Bot Token和Chat ID
4. **删除Telegram Bot通知** - 清除Telegram配置
5. **查看监控域名列表** - 显示所有监控的域名
6. **查看服务状态** - 检查监控服务运行状态
7. **重启监控服务** - 重启域名监控服务
8. **查看运行日志** - 实时查看系统日志
9. **卸载监控系统** - 完全卸载系统

## 常用命令

```bash
# 查看服务状态
systemctl status domainmonitor

# 查看日志
tail -f /opt/domainmonitor/logs/monitor.log

# 重启服务
systemctl restart domainmonitor

# 停止服务
systemctl stop domainmonitor

# 启动服务
systemctl start domainmonitor
```

## 配置文件说明

配置文件位置：`/opt/domainmonitor/config.json`

```json
{
  "telegram": {
    "bot_token": "YOUR_BOT_TOKEN",
    "chat_id": "YOUR_CHAT_ID"
  },
  "check_interval": 60
}
```

- `bot_token`: Telegram Bot的Token
- `chat_id`: 接收通知的Chat ID
- `check_interval`: 检查间隔（分钟）

## 通知内容示例

### 域名可注册通知
```
🔔 域名监控通知

域名: example.com
时间: 2025-01-29 10:30:45

状态: ✅ 可以注册！

🎯 立即行动!
该域名现在可以注册，建议立即前往以下注册商注册：

推荐注册商:
• Namecheap - 价格实惠
• GoDaddy - 全球最大
• Cloudflare - 成本价
• Porkbun - 性价比高

💡 注册建议:
• 建议注册5-10年获得优惠
• 开启域名隐私保护(WHOIS Privacy)
• 开启自动续费避免过期
• 使用Cloudflare等可靠DNS
• 立即设置域名锁防止转移

⚡ 请尽快行动，好域名稍纵即逝！
```

### 域名即将过期通知
```
🔔 域名监控通知

域名: example.com
时间: 2025-01-29 10:30:45

状态: ❌ 已被注册
过期时间: 2025-02-15
剩余天数: ⚠️ 17 天

💡 域名即将过期，持续监控中...
```

## 故障排除

### 1. 服务无法启动
```bash
# 查看详细错误
journalctl -u domainmonitor -n 50

# 检查Python依赖
pip3 list | grep -E "requests|telegram|schedule"

# 重新安装依赖
pip3 install -r /opt/domainmonitor/requirements.txt
```

### 2. Telegram通知不工作
```bash
# 测试网络连接
ping -c 4 api.telegram.org

# 手动发送测试消息
curl -X POST "https://api.telegram.org/bot<TOKEN>/sendMessage" \
     -d "chat_id=<CHAT_ID>" \
     -d "text=Test message"
```

### 3. 域名检查失败
```bash
# 测试whois命令
whois google.com

# 如果whois不可用，安装它
apt-get install whois  # Debian/Ubuntu
yum install whois      # CentOS/RHEL
```

## 更新日志

### v1.0.0 (2025-07-29)
- 初始版本发布
- 支持域名状态监控
- Telegram Bot通知
- 多种通知方式支持（python-telegram-bot、requests、curl）
- 域名过期提醒
- 完整的管理界面

## 贡献

欢迎提交Issue和Pull Request！

## 许可证

MIT License

## 作者

- GitHub: [everett7623](https://github.com/everett7623)
