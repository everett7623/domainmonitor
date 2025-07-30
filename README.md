# DomainMonitor - 域名监控系统

<p align="center">
  <img src="https://img.shields.io/badge/version-2.0.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/python-3.6+-green.svg" alt="Python">
  <img src="https://img.shields.io/badge/license-MIT-yellow.svg" alt="License">
  <img src="https://img.shields.io/badge/platform-Linux-orange.svg" alt="Platform">
</p>

<p align="center">
  <b>🔍 自动监控域名注册状态，让心仪域名不再错过</b>
</p>

## 🌟 功能特点

- 🔍 **自动检测**：定期检查域名的注册状态
- 📱 **即时通知**：通过 Telegram Bot 发送详细通知
- 📊 **状态追踪**：记录每个域名的检查历史
- ⏰ **到期提醒**：域名即将到期时自动提醒（30/7/3/1天）
- 🛠️ **易于管理**：提供友好的命令行管理界面
- 📝 **详细日志**：完整的运行日志记录
- 🚀 **批量监控**：支持同时监控多个域名
- 🔄 **灵活配置**：可自定义检查间隔和提醒时间

## 📋 系统要求

- Linux 系统（支持 Ubuntu/Debian/CentOS）
- Python 3.6 或更高版本
- Root 权限（用于安装系统服务）
- 网络连接（用于查询域名状态和发送通知）

## 🚀 快速安装

使用一键安装脚本：

```bash
bash <(curl -sSL https://raw.githubusercontent.com/everett7623/domainmonitor/main/install.sh)
```

或者下载后执行：

```bash
wget https://raw.githubusercontent.com/everett7623/domainmonitor/main/install.sh
chmod +x install.sh
sudo ./install.sh
```

## 📱 Telegram Bot 配置

### 1. 创建 Bot

1. 在 Telegram 中搜索 **@BotFather**
2. 发送 `/newbot` 创建新机器人
3. 按提示设置机器人名称（如：Domain Monitor）
4. 设置用户名（必须以bot结尾，如：domainmonitor_bot）
5. 获得 **Bot Token**（格式：1234567890:ABCdefGHIjklMNOpqrsTUVwxyz）

### 2. 获取 Chat ID

1. 搜索并打开您刚创建的机器人
2. 发送任意消息（如：Hello）
3. 在浏览器访问：`https://api.telegram.org/bot<BOT_TOKEN>/getUpdates`
4. 在返回的 JSON 中找到 `"chat":{"id":数字}`，这个数字就是 Chat ID

### 3. 配置通知

在安装过程中或通过管理菜单配置 Bot Token 和 Chat ID。

## 📖 使用指南

### 管理命令

安装完成后，使用以下命令打开管理菜单：

```bash
/opt/domainmonitor/manage.sh
```

### 管理菜单功能

```
========================================
        域名监控管理系统 v2.0          
========================================
1. 添加监控域名
2. 删除监控域名
3. 配置Telegram Bot通知
4. 删除Telegram Bot通知
5. 查看监控域名列表
6. 查看服务状态
7. 重启监控服务
8. 查看运行日志
9. 立即检查所有域名
10. 修改检查间隔
11. 查看检查历史
12. 高级设置
13. 卸载监控系统
0. 退出
========================================
```

### 常用操作

#### 添加域名
```bash
# 可以一次添加多个域名
示例：example.com domain.net test.org
```

#### 查看日志
```bash
tail -f /opt/domainmonitor/logs/monitor.log
```

#### 服务管理
```bash
# 查看状态
systemctl status domainmonitor

# 重启服务
systemctl restart domainmonitor

# 停止服务
systemctl stop domainmonitor

# 启动服务
systemctl start domainmonitor
```

## 📬 通知内容

### 域名可注册通知

当监控的域名变为可注册状态时，您将收到：

```
🔔 域名监控通知

域名: example.com
时间: 2025-01-29 10:30:00

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

### 域名到期提醒

在域名到期前的30天、7天、3天和1天，您将收到提醒通知。

## 🔧 高级设置

### 修改检查间隔

默认每60分钟检查一次，可根据需求调整：

- **5分钟**：紧急监控（域名即将释放）
- **15分钟**：高频监控（重要域名）
- **30分钟**：常规监控
- **60分钟**：标准监控（默认）
- **120分钟**：低频监控（一般关注）
- **360分钟**：每日检查（长期关注）

### 自定义提醒天数

可以自定义域名到期前多少天发送提醒，默认为：30、7、3、1天。

### 批量导入域名

支持从文本文件批量导入域名列表，每行一个域名。

## 📁 文件结构

```
/opt/domainmonitor/
├── domain_monitor.py    # 主监控程序
├── manage.sh           # 管理脚本
├── config.json         # 配置文件
├── domains.txt         # 域名列表
├── history.json        # 历史记录
└── logs/
    └── monitor.log     # 运行日志
```

## 🐛 常见问题

### 1. 无法收到Telegram通知

- 检查 Bot Token 和 Chat ID 是否正确
- 确保已经给机器人发送过消息
- 检查网络是否能访问 Telegram API

### 2. whois命令不可用

部分系统可能需要手动安装：

```bash
# Ubuntu/Debian
apt-get install whois

# CentOS
yum install whois
```

### 3. 服务无法启动

查看详细错误信息：

```bash
journalctl -u domainmonitor -n 50
```

## 🤝 贡献

欢迎提交 Issue 和 Pull Request！

## 📄 许可证

本项目采用 MIT 许可证。详见 [LICENSE](LICENSE) 文件。

## 👨‍💻 作者

- **everett7623**
- GitHub: [https://github.com/everett7623](https://github.com/everett7623)

## 🌟 Star History

如果这个项目对您有帮助，请给个 Star ⭐ 支持一下！

---

<p align="center">
  Made with ❤️ by everett7623
</p>
