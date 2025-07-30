# DomainMonitor - 域名状态监控系统

<p align="center">
  <img src="https://img.shields.io/badge/version-v1.0.0-blue.svg" alt="Version">
  <img src="https://img.shields.io/badge/python-3.7+-green.svg" alt="Python">
  <img src="https://img.shields.io/badge/license-MIT-yellow.svg" alt="License">
</p>

## 🌟 项目介绍

DomainMonitor 是一个专业的域名状态监控工具，帮助您实时监控心仪域名的注册状态。当域名可以注册时，系统会通过 Telegram Bot 立即通知您，让您不错过任何抢注机会。

## ✨ 功能特点

- 🔍 **自动检测**：定期检查域名的注册状态
- 📱 **即时通知**：通过 Telegram Bot 发送详细通知
- 📊 **状态追踪**：记录每个域名的检查历史
- ⏰ **到期提醒**：域名即将到期时自动提醒
- 🛠️ **易于管理**：提供简单的命令行管理工具
- 📝 **详细日志**：完整的运行日志记录

## 🚀 快速开始

### 一键安装

```bash
bash <(curl -sSL https://raw.githubusercontent.com/everett7623/domainmonitor/main/install.sh)
```

### 系统要求

- Linux 系统（Ubuntu/Debian/CentOS）
- Python 3.7+
- Root 权限
- 稳定的网络连接

## 📱 Telegram Bot 设置

1. 在 Telegram 中找到 [@BotFather](https://t.me/BotFather)
2. 发送 `/newbot` 创建新机器人
3. 按提示设置机器人名称和用户名
4. 获取 Bot Token
5. 通过 [@userinfobot](https://t.me/userinfobot) 获取您的 Chat ID

## 🔧 使用方法

### 服务管理

```bash
# 启动服务
domainctl start

# 停止服务
domainctl stop

# 重启服务
domainctl restart

# 查看状态
domainctl status
```

### 域名管理

```bash
# 添加域名
domainctl add example.com

# 删除域名
domainctl remove example.com

# 列出所有域名
domainctl list

# 立即检查
domainctl check
```

### 日志查看

```bash
# 查看最近日志
domainctl logs

# 实时查看日志
domainctl logs -f

# 查看错误日志
domainctl logs -e
```

### 其他命令

```bash
# 编辑配置
domainctl config

# 更新程序
domainctl update

# 卸载程序
domainctl uninstall
```

## 📄 配置文件

配置文件位于 `/opt/domainmonitor/config/config.json`

```json
{
    "telegram": {
        "bot_token": "YOUR_BOT_TOKEN",
        "chat_id": "YOUR_CHAT_ID"
    },
    "check_interval": 300,
    "domains": [
        "example.com",
        "test.com"
    ],
    "registrars": [
        {
            "name": "Namecheap",
            "url": "https://www.namecheap.com",
            "features": ["价格实惠", "免费隐私保护", "支持支付宝"]
        }
    ]
}
```

### 配置说明

- `telegram.bot_token`: Telegram Bot Token
- `telegram.chat_id`: 接收通知的 Chat ID
- `check_interval`: 检查间隔（秒），默认 300 秒
- `domains`: 监控的域名列表
- `registrars`: 推荐的域名注册商

## 📬 通知内容

当域名可以注册时，您将收到包含以下信息的通知：

- 域名名称和当前状态
- 检测时间
- 推荐的域名注册商列表
- 注册建议（如注册年限、隐私保护等）
- 紧急行动提醒

### 通知示例

```
🎉 域名可以注册啦！ 🎉

📌 域名: example.com
⏰ 检测时间: 2024-01-01 12:00:00
🔥 状态: 可注册

📋 推荐注册商:
▫️ Namecheap
  🔗 https://www.namecheap.com
  ✨ 价格实惠, 免费隐私保护, 支持支付宝

💡 注册建议:
• 建议注册 3-5 年，价格更优惠
• 开启域名隐私保护
• 设置自动续费避免过期
• 立即注册，好域名稍纵即逝！

⚡ 紧急行动: 请立即前往注册商抢注！
```

## 📁 目录结构

```
/opt/domainmonitor/
├── domainmonitor.py      # 主程序
├── domainctl.sh         # 管理脚本
├── requirements.txt     # Python 依赖
├── config/             # 配置目录
│   └── config.json     # 配置文件
├── data/               # 数据目录
│   └── history.json    # 历史记录
├── logs/               # 日志目录
│   ├── domainmonitor.log      # 运行日志
│   └── domainmonitor.error.log # 错误日志
└── venv/               # Python 虚拟环境
```

## 🔒 安全建议

1. **保护 Bot Token**：不要将 Bot Token 分享给他人
2. **定期备份**：定期备份配置文件和历史数据
3. **更新程序**：定期运行 `domainctl update` 获取最新版本
4. **监控日志**：定期检查日志文件，及时发现问题

## 🤝 贡献指南

欢迎提交 Issue 和 Pull Request！

1. Fork 本仓库
2. 创建您的特性分支 (`git checkout -b feature/AmazingFeature`)
3. 提交您的更改 (`git commit -m 'Add some AmazingFeature'`)
4. 推送到分支 (`git push origin feature/AmazingFeature`)
5. 开启一个 Pull Request

## 📝 更新日志

### v1.0.0 (2025-07-30)
- 🎉 首次发布
- ✨ 支持域名状态监控
- 📱 Telegram Bot 通知
- 🛠️ 完整的管理工具
- 📊 历史记录功能

## 📄 许可证

本项目采用 MIT 许可证 - 查看 [LICENSE](LICENSE) 文件了解详情

## 👨‍💻 作者

- **everett7623** - [GitHub](https://github.com/everett7623)

## 🙏 致谢

感谢所有为这个项目做出贡献的人！

---

<p align="center">
  Made with ❤️ by everett7623
</p>
